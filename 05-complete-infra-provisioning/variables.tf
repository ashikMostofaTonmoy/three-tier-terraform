variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

variable "instance_type" {
  description = "Runs Postgres + Node (PM2 cluster) + Nginx on one box, so t3.micro's 1GB RAM is tight — t3.small gives headroom"
  type        = string
  default     = "t3.small"
}

variable "db_name" {
  type    = string
  default = "three_tier"
}

variable "db_user" {
  type    = string
  default = "three_tier_user"
}
