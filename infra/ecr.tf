resource "aws_ecr_repository" "app_repo" {
  name                 = var.service_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "FreeTier-Study"
    Service     = var.service_name
  }
}

# Mantém as últimas 10 imagens (API + worker contam juntas). A regra antiga
# (sinceImagePushed 5 dias) apagava TUDO quando ninguém fazia push por 5 dias.
resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
