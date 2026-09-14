variable "name" {
  description = "Name for the IAM role / instance profile, e.g. \"three-tier-terraform-05-ec2\""
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager ARNs this instance may GetSecretValue on"
  type        = list(string)
  default     = []
}

variable "s3_read_arns" {
  description = "S3 object ARNs (e.g. \"arn:...:bucket/*\") this instance may GetObject on"
  type        = list(string)
  default     = []
}

variable "enable_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore — lets you reach the instance with `aws ssm start-session`/`send-command` with zero inbound security group rules, for debugging without SSH"
  type        = bool
  default     = true
}
