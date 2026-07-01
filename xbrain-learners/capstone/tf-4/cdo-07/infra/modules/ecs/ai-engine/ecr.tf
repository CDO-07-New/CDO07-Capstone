resource "aws_ecr_repository" "ai_engine" {
  name                 = "cdo-07-ai-engine"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = var.tags
}

resource "null_resource" "push_ai_image" {
  triggers = {
    repository_url = aws_ecr_repository.ai_engine.repository_url
    source_image   = "public.ecr.aws/nginx/nginx:1.26-alpine"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<EOT
      $ErrorActionPreference = "Stop"
      $Region = "${var.aws_region}"
      $RepoUrl = "${aws_ecr_repository.ai_engine.repository_url}"
      $SourceImage = "public.ecr.aws/nginx/nginx:1.26-alpine"

      $Pass = aws ecr get-login-password --region $Region
      docker login --username AWS --password $Pass $RepoUrl
      docker pull $SourceImage
      docker tag $SourceImage "$($RepoUrl):v1.0.0"
      docker push "$($RepoUrl):v1.0.0"
    EOT
  }
}
