terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto centralizado (S3 + DynamoDB)
  backend "s3" {
    bucket         = "fiap-tech-challenge-tfstate-123456-915153720516-sa-east-1-an" # Substitua pelo seu Bucket S3
    key            = "payments-service/terraform.tfstate"                           # Key exclusiva deste microsserviço
    region         = "sa-east-1"                                                    # Sua região AWS
    dynamodb_table = "fiap-tech-challenge-tflocks"                                  # Nome da sua tabela DynamoDB
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}