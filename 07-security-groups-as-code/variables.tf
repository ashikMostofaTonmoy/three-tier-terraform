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
