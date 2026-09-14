variable "identifier" {
  type = string
}

variable "subnet_ids" {
  description = "Private DB subnets (at least 2, different AZs) for the DB subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  description = "GB"
  type        = number
  default     = 20
}
