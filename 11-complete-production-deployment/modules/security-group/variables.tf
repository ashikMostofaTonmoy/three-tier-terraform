variable "name_prefix" {
  type    = string
  default = "three-tier-terraform-07"
}

variable "vpc_id" {
  description = "Required — pass the default VPC's ID explicitly if that's what you want (see the lesson 07 README for why this can't default to a lookup inside the module)"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP, as a /32 CIDR — the only source allowed to SSH into the bastion group"
  type        = string
}
