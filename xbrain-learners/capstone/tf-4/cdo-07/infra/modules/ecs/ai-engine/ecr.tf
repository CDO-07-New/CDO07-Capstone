resource "aws_ecr_repository" "ai_engine" {
  name                 = "cdo-07-ai-engine"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = var.tags
}

resource "null_resource" "push_ai_image" {
  triggers = {
    repository_url = aws_ecr_repository.ai_engine.repository_url
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<EOT
      $ErrorActionPreference = "Stop"
      $Region = "${var.aws_region}"
      $RepoUrl = "${aws_ecr_repository.ai_engine.repository_url}"

      $Pass = aws ecr get-login-password --region $Region
      docker login --username AWS --password $Pass $RepoUrl
      
      Write-Host "Building Docker Image for AI Engine..."
      docker build -t "$($RepoUrl):v1.0.0" "..\..\..\final-build"
      
      Write-Host "Pushing Docker Image to ECR..."
      docker push "$($RepoUrl):v1.0.0"
    EOT
  }
}
