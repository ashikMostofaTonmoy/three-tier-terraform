variable "name" {
  description = "Name for the ASG, its launch template prefix, and the instances' Name tag"
  type        = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_ids" {
  description = "Spread across these — pass subnets in 2+ AZs so losing one AZ doesn't take the tier down"
  type        = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "iam_instance_profile" {
  type = string
}

variable "user_data" {
  description = "Rendered (not base64) boot script — the module encodes it"
  type        = string
}

variable "target_group_arns" {
  description = "ALB target groups the ASG registers every instance into automatically"
  type        = list(string)
  default     = []
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "desired_capacity" {
  description = "Starting size only — scaling policies own this number after the first apply (see ignore_changes in main.tf)"
  type        = number
}

variable "health_check_grace_period" {
  description = "Seconds after launch before failed health checks count — must cover boot + app start"
  type        = number
  default     = 180
}

variable "target_cpu" {
  description = "Target tracking: keep average CPU near this %. null = no target tracking policy."
  type        = number
  default     = null
}

variable "step_scaling" {
  description = "Create a step scaling policy pair driven by explicit CloudWatch alarms (+1 above 60% CPU, +2 above 80%, -1 below 20%)"
  type        = bool
  default     = false
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
