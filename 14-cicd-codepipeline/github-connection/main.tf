# The one piece of the CI/CD setup Terraform can create but cannot finish:
# AWS creates the connection in PENDING state, and a human must approve it
# once in the console (it installs the "AWS Connector for GitHub" app on
# your GitHub account). Kept in its own folder so destroying and
# recreating the pipeline lesson never forces you to re-authorize.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key = "14-cicd-codepipeline/github-connection/terraform.tfstate"
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

resource "aws_codestarconnections_connection" "github" {
  name          = "three-tier-terraform-github"
  provider_type = "GitHub"
}

output "connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "connection_status" {
  description = "PENDING until approved in the console; AVAILABLE after"
  value       = aws_codestarconnections_connection.github.connection_status
}
