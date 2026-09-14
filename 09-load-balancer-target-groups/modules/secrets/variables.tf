variable "name" {
  description = "Secrets Manager secret name, e.g. \"three-tier-terraform/05/db-password\""
  type        = string
}

variable "password_length" {
  type    = number
  default = 24
}
