# --- VARIÁVEIS GLOBAIS ---
variable "aws_region" {
  type    = string
  default = "sa-east-1"
}

variable "service_name" {
  type    = string
  default = "fcg-payments-service"
}

variable "app_port" {
  type    = number
  default = 5003 # Porta exposta do container Spring Boot/Node
}

variable "cluster_name" {
  type = string
  # Cluster dedicado deste serviço. NÃO usar um nome compartilhado entre serviços
  # (ex.: "fcg-cluster-fiap" usado por todos) — quando várias ASGs de serviços
  # diferentes registram suas EC2 no MESMO cluster, o ECS trata a capacidade como
  # única e pode agendar a task de um serviço na instância dedicada de outro
  # (já aconteceu: task do users-service rodando numa EC2 do catalog-service).
  # Cada serviço aqui já lança sua própria EC2 dedicada — não tem economia real em
  # compartilhar o nome, só a ambiguidade de agendamento.
  default = "fcg-payments-cluster"
}