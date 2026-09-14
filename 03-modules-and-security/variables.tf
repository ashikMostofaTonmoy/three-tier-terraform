variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

# This variable is never read by any resource. It exists solely to
# demonstrate how Terraform handles sensitive values, before lesson 08
# wires a real secret (a DB password) through Secrets Manager. Try running
# `terraform plan` with and without `sensitive = true` here and compare the
# console output — see README section 4.
variable "demo_secret" {
  description = "Not used by any resource — demonstrates sensitive-value redaction only"
  type        = string
  default     = "not-a-real-secret"
  sensitive   = true
}
