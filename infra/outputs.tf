output "ecs_cluster_name" {
  description = "Nome do Cluster ECS criado"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_id" {
  description = "ARN/ID do Cluster ECS criado"
  value       = aws_ecs_cluster.main.id
}

output "ecs_service_name" {
  description = "Nome do Serviço ECS em execução"
  value       = aws_ecs_service.main.name
}

output "ecs_security_group_id" {
  description = "ID do Security Group associado às instâncias do ECS"
  value       = aws_security_group.ecs_sg.id
}