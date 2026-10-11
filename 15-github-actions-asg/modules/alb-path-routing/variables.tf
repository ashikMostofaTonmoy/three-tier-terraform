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
  description = "Paths the ALB sends straight to the backend target group; everything else goes to the frontend"
  type        = list(string)
  default     = ["/api/*", "/health"]
}
