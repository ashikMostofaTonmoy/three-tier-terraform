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

variable "github_immutable_sub_prefix" {
  description = <<-EOT
    Newer GitHub repos put owner/repo IDs in the OIDC token's subject:
    "repo:OWNER@OWNER_ID/REPO@REPO_ID". Get yours with
      gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
    Leave empty if that shows use_immutable_subject = false.
  EOT
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = "An AWS account can hold only ONE token.actions.githubusercontent.com provider. Set false if your account already has it (e.g. from three-tier-deployment)."
  type        = bool
  default     = true
}

variable "backend_instance_type" {
  description = "t3.micro (not t3.small as in 13-15): there are TWO backend fleets here, so each one is kept small"
  type        = string
  default     = "t3.micro"
}

variable "backend_per_color" {
  description = "Instances in EACH color's ASG. Both colors run all the time in this lesson so rollback is instant — see README §7 for the scale-idle-to-zero variant"
  type        = number
  default     = 2
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
