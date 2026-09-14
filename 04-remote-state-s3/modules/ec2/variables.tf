variable "name" {
  description = "Value for the instance's Name tag, and prefix for other tags"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "security_group_ids" {
  description = "Security group IDs to attach. Empty list = default VPC's default SG."
  type        = list(string)
  default     = []
}

variable "extra_tags" {
  description = "Additional tags merged onto the instance"
  type        = map(string)
  default     = {}
}
