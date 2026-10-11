variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

variable "github_repo" {
  description = "owner/name — only workflows in THIS repo may assume the deploy role"
  type        = string
  default     = "ashikMostofaTonmoy/three-tier-terraform"
}

variable "github_branches" {
  description = "Only workflow runs on these branches may assume the deploy role"
  type        = list(string)
  default     = ["main"]
}

variable "create_github_oidc_provider" {
  description = "An AWS account can hold only ONE token.actions.githubusercontent.com provider. Set false if your account already has it (e.g. from three-tier-deployment)."
  type        = bool
  default     = true
}

variable "backend_instance_type" {
  type    = string
  default = "t3.small"
}

variable "frontend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_name" {
  type    = string
  default = "three_tier"
}

variable "db_user" {
  type    = string
  default = "three_tier_user"
}
