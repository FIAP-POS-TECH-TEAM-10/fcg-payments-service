# 1. Definição da HTTP API (v2) - Ideal para Free Tier
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.service_name}-api-gateway"
  protocol_type = "HTTP"
  description   = "API Gateway público do PaymentsAPI (FCGames)"
}

# Captura o IP público da EC2 do ECS. Escopado por tag Name + tag de ASG
# (aws:autoscaling:groupName) pra pegar só a instância desta ASG. Como o cluster já é
# dedicado a este serviço (ver infra/variables.tf, cluster_name), só a própria ASG
# registra instâncias com essa tag — "qualquer" candidata já é a certa, sem ambiguidade.
#
# NÃO usar `for_each` sobre `data.aws_instances...ids` aqui: numa apply "cold start"
# (cluster e ASG sendo criados na mesma apply) essa lista só é conhecida DEPOIS do
# apply, e o Terraform exige que as chaves de um for_each sejam conhecidas ANTES — dá
# erro "Invalid for_each argument". Ler direto o índice [0] não tem essa restrição.
data "aws_instances" "ecs_host_candidates" {
  instance_tags = {
    Name = "${var.service_name}-ecs-host"
  }
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.ecs_asg.name]
  }

  instance_state_names = ["running"]
  depends_on           = [aws_autoscaling_group.ecs_asg]
}

locals {
  ecs_host_ip = data.aws_instances.ecs_host_candidates.public_ips[0]
}

# 2. Integração do API Gateway com o IP público da EC2 do ECS.
# `/{proxy}` no fim é obrigatório: sem isso a HTTP API repassa TODA requisição para a
# raiz "/" do backend (todo endpoint vira 404). Com `{proxy}` ela injeta o caminho
# capturado pela rota `ANY /{proxy+}` (ex.: /health, /pagamentos/{orderId}).
resource "aws_apigatewayv2_integration" "ecs_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "HTTP_PROXY"
  integration_uri        = "http://${local.ecs_host_ip}:${var.app_port}/{proxy}"
  integration_method     = "ANY"
  payload_format_version = "1.0"

  # A rota `ANY /` não tem a variável `proxy`; ela precisa ser repontada para a
  # integração raiz ANTES de esta integração ganhar `/{proxy}`, senão a AWS
  # rejeita a validação rota<->integração ("path variables ... not present in the route key").
  depends_on = [aws_apigatewayv2_route.root_route]
}

# 3. Rota coringa: repassa todos os endpoints (/health, /pagamentos/{orderId}, ...) para o ECS.
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.ecs_integration.id}"
}

# Rota para a raiz "/" — usa integração própria, forçando o path "/" no backend
# (não dá pra reaproveitar a integração com `{proxy}` sem um valor pra variável).
resource "aws_apigatewayv2_integration" "ecs_integration_root" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "HTTP_PROXY"
  integration_uri        = "http://${local.ecs_host_ip}:${var.app_port}/"
  integration_method     = "ANY"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "root_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.ecs_integration_root.id}"
}

# Output para exibir a URL final gerada pelo API Gateway
output "api_gateway_url" {
  description = "URL HTTPS pública gerada pelo API Gateway (Free Tier)"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

# 1. Role do IAM para o serviço do API Gateway conseguir escrever no CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.service_name}-apigw-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# 2. Anexa a política gerenciada da AWS para gravação de logs
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# 3. Associa a Role criada às configurações globais do API Gateway da conta na região
resource "aws_api_gateway_account" "account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch_policy]
}

# 3. Política de Recurso que concede permissão EXPLÍCITA ao CloudWatch para o API Gateway
resource "aws_cloudwatch_log_resource_policy" "api_gw_logging_policy" {
  policy_name = "${var.service_name}-apigw-cw-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:ConfigureLogDelivery",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.api_gw_logs.arn}:*"
      }
    ]
  })
}

# 1. Log Group no CloudWatch para armazenar os Access Logs do API Gateway
resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/${var.service_name}-api-gateway"
  retention_in_days = 7
}

# 2. Atualização do Stage $default com Access Logs habilitados
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    logging_level            = "INFO"
    detailed_metrics_enabled = true
    throttling_burst_limit   = 10000
    throttling_rate_limit    = 20000
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      path                    = "$context.path"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      integrationStatus       = "$context.integrationStatus"
      integrationLatency      = "$context.integration.latency"
      errorMessage            = "$context.error.message"
      errorResponseType       = "$context.error.responseType"
      latency                 = "$context.responseLatency"
    })
  }

  depends_on = [
    aws_cloudwatch_log_resource_policy.api_gw_logging_policy
  ]
}
