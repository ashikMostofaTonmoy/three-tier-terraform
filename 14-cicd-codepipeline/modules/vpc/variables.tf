variable "name" {
  description = "Prefix for every resource name/tag this module creates"
  type        = string
}

variable "cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

# Matches three-tier-deployment's Part 5/6 shell-script VPC exactly — same
# CIDR layout, same 2-AZ/3-tier subnet split, this time as Terraform
# resources instead of a bash loop over `aws ec2 create-subnet`.
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.20.0/24", "10.0.21.0/24"]
}
