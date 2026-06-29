# Temporary import blocks — delete this file after `terraform apply` succeeds
# These import pre-existing AWS resources into Terraform state.

# ECR Repositories
import {
  to = aws_ecr_repository.services["ingest-service"]
  id = "tf4-cdo07-ingest-service"
}

import {
  to = aws_ecr_repository.services["ingest-worker"]
  id = "tf4-cdo07-ingest-worker"
}

import {
  to = aws_ecr_repository.services["ai-serving"]
  id = "tf4-cdo07-ai-serving"
}

# ECR Lifecycle Policies
import {
  to = aws_ecr_lifecycle_policy.services["ingest-service"]
  id = "tf4-cdo07-ingest-service"
}

import {
  to = aws_ecr_lifecycle_policy.services["ingest-worker"]
  id = "tf4-cdo07-ingest-worker"
}

import {
  to = aws_ecr_lifecycle_policy.services["ai-serving"]
  id = "tf4-cdo07-ai-serving"
}

# IAM Policies
import {
  to = aws_iam_policy.github_plan
  id = "arn:aws:iam::201023212626:policy/tf4-cdo07-github-plan-policy"
}

import {
  to = aws_iam_policy.github_deploy
  id = "arn:aws:iam::201023212626:policy/tf4-cdo07-github-deploy-policy"
}

# IAM Role Policy Attachments
import {
  to = aws_iam_role_policy_attachment.github_plan
  id = "tf4-cdo07-github-plan-role/arn:aws:iam::201023212626:policy/tf4-cdo07-github-plan-policy"
}

import {
  to = aws_iam_role_policy_attachment.github_deploy
  id = "tf4-cdo07-github-deploy-role/arn:aws:iam::201023212626:policy/tf4-cdo07-github-deploy-policy"
}
