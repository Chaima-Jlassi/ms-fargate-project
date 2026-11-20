terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # State is stored locally by default. For real use, keep it in S3 with
  # locking, for example:
  #
  # backend "s3" {
  #   bucket       = "my-terraform-state-bucket"
  #   key          = "ecs-fargate-microservices/terraform.tfstate"
  #   region       = "eu-north-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets these tags: useful for cost tracking and cleanup.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
