variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "At least 2, different AZs — the ALB itself requires this"
  type        = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "target_instance_id" {
  type = string
}

variable "target_port" {
  type    = number
  default = 80
}

variable "health_check_path" {
  type    = string
  default = "/health"
}
