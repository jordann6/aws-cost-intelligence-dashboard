terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket       = "tf-state-jordprojs"
    key          = "aws-cost-intelligence-dashboard/dev.terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  # FinOps: every resource inherits these; nothing can be created untagged.
  # Keys are TitleCase to match the required_tags compliance list exactly.
  default_tags {
    tags = {
      Project     = "cost-dashboard"
      Environment = var.environment
      Owner       = "jordann6"
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
      Team        = var.team
    }
  }
}
