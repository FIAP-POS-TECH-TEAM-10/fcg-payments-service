# ------------------------------------------------------------------------------
# 1. REDE PADRÃO E SECURITY GROUP
# ------------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group liberando a porta da aplicação e HTTP
resource "aws_security_group" "ecs_sg" {
  name        = "${var.service_name}-ecs-sg"
  description = "Permite trafego de entrada para o container ECS"
  vpc_id      = data.aws_vpc.default.id

  # Libera portas dinâmicas alocadas pelo ECS no modo bridge (32768-61000)
  ingress {
    from_port   = 32768
    to_port     = 61000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------------------------------
# 2. CLOUDWATCH LOGS & PERMISSÕES IAM DO ECS
# ------------------------------------------------------------------------------

# Grupo de logs para capturar stdout/stderr das tasks do ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.service_name}"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.service_name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Política padrão do ECS Agent
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Permite que a instância EC2 crie e envie streams para o CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_cloudwatch_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.service_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# ------------------------------------------------------------------------------
# 2b. TASK ROLE — usada pelo CONTAINER (não pela instância EC2) para falar com o
#     Amazon SQS/SNS via MassTransit (Messaging:Provider=Sqs). No launch type EC2 o
#     agente injeta AWS_CONTAINER_CREDENTIALS_RELATIVE_URI no container quando a task
#     tem taskRoleArn, e o AWS SDK usa isso automaticamente (sem access key no código).
# ------------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.service_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# MassTransit auto-provisiona (cria) os tópicos SNS e filas SQS na primeira conexão —
# por isso a policy cobre Create/Get/Set além de enviar/receber. Escopo: só recursos
# SQS/SNS da própria conta+região (não IAM, não outros serviços).
resource "aws_iam_role_policy" "ecs_task_sqs_sns" {
  name = "${var.service_name}-task-sqs-sns"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Sqs"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue", "sqs:GetQueueUrl", "sqs:GetQueueAttributes", "sqs:SetQueueAttributes",
          "sqs:TagQueue", "sqs:ListQueueTags", "sqs:SendMessage", "sqs:ReceiveMessage",
          "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:PurgeQueue"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:*:*"
      },
      {
        Sid    = "Sns"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:TagResource",
          "sns:Subscribe", "sns:Unsubscribe", "sns:ListSubscriptionsByTopic", "sns:Publish"
        ]
        Resource = "arn:aws:sns:${var.aws_region}:*:*"
      },
      {
        # sqs:ListQueues e sns:ListTopics não aceitam restrição por ARN de recurso —
        # a AWS exige Resource "*" para essas duas ações (mesmo escopadas só a elas).
        # Sem isso o MassTransit falha (silenciosamente, só loga erro) ao publicar, porque
        # ele chama ListTopics pra checar se o tópico já existe antes de tentar criar.
        Sid      = "ListNoResourceLevelPerms"
        Effect   = "Allow"
        Action   = ["sqs:ListQueues", "sns:ListTopics"]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 3. CLUSTER ECS + LAUNCH TEMPLATE + AUTO SCALING GROUP
# ------------------------------------------------------------------------------

# Cluster ECS
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name
}

# Busca dinamicamente a AMI ECS-Optimized para x86_64
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Template que inicializa a EC2 configurada para o Cluster
resource "aws_launch_template" "ecs_ec2_template" {
  name_prefix   = "${var.service_name}-template-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
              EOF
  )
}

# Auto Scaling Group
resource "aws_autoscaling_group" "ecs_asg" {
  name                = "${var.service_name}-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.ecs_ec2_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.service_name}-ecs-host"
    propagate_at_launch = true
  }
}

# Task Definition configurada com o driver 'awslogs'
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.service_name}-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "256"
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.service_name}-container"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      cpu       = 256
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = 5003
          hostPort      = 5003
          protocol      = "tcp"
        }
      ]
      # VARIÁVEIS DE AMBIENTE PARA DIAGNÓSTICO DO .NET NO LINUX
      environment = [
        { name = "ASPNETCORE_ENVIRONMENT", value = "Development" },      # Revela mais logs no startup
        { name = "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT", value = "1" }, # Evita crash por falta de ICU/locales no Linux
        { name = "DOTNET_USE_POLLING_FILE_WATCHER", value = "true" },
        { name = "Messaging__Provider", value = "Sqs" }, # MassTransit usa Amazon SQS/SNS (ver MassTransitExtensions.cs / Worker/Program.cs)
        { name = "AWS__Region", value = var.aws_region }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# Recurso para registrar e executar a Task no Cluster ECS
resource "aws_ecs_service" "main" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Permite que a capacidade caia para 0 durante o deploy para liberar a porta fixa
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  lifecycle {
    ignore_changes = [
      task_definition # Garante que o Terraform nao reverta as revisoes criadas pelo GitHub Actions
    ]
  }
}