variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

variable "my_ip_cidr" {
  description = "Your public IP, as a /32 CIDR. Find it with: curl -s https://checkip.amazonaws.com"
  type        = string
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "frontend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "backend_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_name" {
  type    = string
  default = "three_tier"
}

variable "db_user" {
  type    = string
  default = "three_tier_user"
}
