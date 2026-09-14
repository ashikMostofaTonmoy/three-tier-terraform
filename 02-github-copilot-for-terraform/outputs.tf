output "instance_id" {
  description = "The instance ID Terraform created"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP — reachable on port 80 once Nginx/a web server is installed"
  value       = aws_instance.web.public_ip
}

output "security_group_id" {
  description = "The security group Copilot helped write"
  value       = aws_security_group.web.id
}
