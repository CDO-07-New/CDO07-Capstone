provider "aws" {
  region     = local.aws_region
  retry_mode = "adaptive"

  default_tags {
    tags = local.common_tags
  }
}
