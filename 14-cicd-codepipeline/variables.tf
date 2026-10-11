variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

variable "github_repo" {
  description = "owner/name of the repo the pipeline builds from — your fork"
  type        = string
  default     = "ashikMostofaTonmoy/three-tier-terraform"
}

variable "github_branch" {
  description = "Only pushes to this branch trigger the pipeline"
  type        = string
  default     = "main"
}

variable "github_connection_name" {
  description = "Name of the CodeStar connection created (and approved) in ./github-connection"
  type        = string
  default     = "three-tier-terraform-github"
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
