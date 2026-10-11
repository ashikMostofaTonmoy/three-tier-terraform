variable "name" {
  description = "Short prefix — target group names are capped at 32 characters"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "backend_paths" {
  type    = list(string)
  default = ["/api/*", "/health"]
}

variable "initial_live_color" {
  description = "Which backend color gets 100% of traffic when the rule is first created. After that the deploy workflow owns the weights (see ignore_changes in main.tf)."
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.initial_live_color)
    error_message = "initial_live_color must be \"blue\" or \"green\"."
  }
}
