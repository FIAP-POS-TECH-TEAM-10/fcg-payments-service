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
  type    = string
  default = "fcg-cluster-fiap"
}