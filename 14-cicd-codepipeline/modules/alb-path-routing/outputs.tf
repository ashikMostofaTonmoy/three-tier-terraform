output "dns_name" {
  value = aws_lb.this.dns_name
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arn" {
  value = aws_lb_target_group.backend.arn
}

output "frontend_target_group_name" {
  value = aws_lb_target_group.frontend.name
}

output "backend_target_group_name" {
  value = aws_lb_target_group.backend.name
}
