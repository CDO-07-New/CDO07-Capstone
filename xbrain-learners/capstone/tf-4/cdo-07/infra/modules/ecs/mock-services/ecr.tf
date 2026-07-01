locals {
  mock_services_list = ["payment-gw", "ledger-svc", "fraud-detection"]
}

resource "aws_ecr_repository" "mock_repos" {
  for_each = toset(local.mock_services_list)

  name                 = "cdo-07-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = var.tags
}

resource "null_resource" "push_mock_image" {
  for_each = toset(local.mock_services_list)

  triggers = {
    repository_url = aws_ecr_repository.mock_repos[each.key].repository_url
    source_image   = "public.ecr.aws/nginx/nginx:1.26-alpine"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<EOT
      $ErrorActionPreference = "Stop"
      $Region = "${var.aws_region}"
      $RepoUrl = "${aws_ecr_repository.mock_repos[each.key].repository_url}"
      $SourceImage = "public.ecr.aws/nginx/nginx:1.26-alpine"

      $Pass = aws ecr get-login-password --region $Region
      docker login --username AWS --password $Pass $RepoUrl
      docker pull $SourceImage
      docker tag $SourceImage "$($RepoUrl):v1.0.0"
      docker push "$($RepoUrl):v1.0.0"
    EOT
  }
}
