# The provider is the plugin that translates HCL into actual AWS API calls.
# `profile` here is the same named AWS CLI profile ("ostad") used by every
# script in the three-tier-deployment repo — Terraform reads the exact same
# ~/.aws/credentials file, nothing new to configure.
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
