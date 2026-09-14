terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Deliberately left partial — bucket/dynamodb_table/region come from
  # backend.hcl (gitignored, since the bucket name embeds the AWS account
  # ID) via: terraform init -backend-config=backend.hcl
  # See backend.hcl.example and README section 2.
  backend "s3" {
    key = "04-remote-state-s3/terraform.tfstate"
  }
}
