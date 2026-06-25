resource "aws_kms_key" "bootstrap" {
  description             = "KMS key for ${local.name_prefix} Terraform state and ECR encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_key_policy.json
}

resource "aws_kms_alias" "bootstrap" {
  name          = "alias/${local.name_prefix}-bootstrap"
  target_key_id = aws_kms_key.bootstrap.key_id
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid    = "AllowAccountRootFullAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCicdRolesToUseKey"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.github_plan.arn,
        aws_iam_role.github_deploy.arn,
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
    ]

    resources = ["*"]
  }
}
