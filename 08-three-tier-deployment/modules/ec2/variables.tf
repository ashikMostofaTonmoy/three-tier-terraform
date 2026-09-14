variable "name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "subnet_id" {
  description = "null = the default VPC's default subnet"
  type        = string
  default     = null
}

variable "associate_public_ip" {
  type    = bool
  default = null
}

variable "iam_instance_profile" {
  type    = string
  default = null
}

variable "user_data" {
  type    = string
  default = null
}

variable "root_volume_size" {
  description = "GB"
  type        = number
  default     = 20
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
