variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

variable "app_version" {
  description = "Written into each instance's boot script. Changing it creates a new launch template version, which triggers a rolling instance refresh — the IaC way to roll every instance."
  type        = string
  default     = "1"
}

variable "backend_instance_type" {
  type    = string
  default = "t3.small"
}

variable "frontend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "backend_min" {
  type    = number
  default = 2
}

variable "backend_max" {
  type    = number
  default = 4
}

variable "frontend_min" {
  type    = number
  default = 2
}

variable "frontend_max" {
  type    = number
  default = 3
}

variable "db_name" {
  type    = string
  default = "three_tier"
}

variable "db_user" {
  type    = string
  default = "three_tier_user"
}
