terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "tf4-cdo07-tf-state-201023212626-use1"
    key          = "tf4-cdo07/staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
