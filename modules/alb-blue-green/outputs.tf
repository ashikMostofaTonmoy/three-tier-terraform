output "dns_name" {
  value = aws_lb.this.dns_name
}

output "frontend_target_group_arn" {
  value = aws_lb_target_group.frontend.arn
}

output "backend_target_group_arns" {
  description = "map: color → target group ARN"
  value       = { for c, tg in aws_lb_target_group.backend : c => tg.arn }
}

output "weighted_rule_arn" {
  value = aws_lb_listener_rule.backend_weighted.arn
}
