output "alb_dns_name" {
  value = module.alb.dns_name
}

output "app_url" {
  value = "http://${module.alb.dns_name}"
}

output "backend_private_ip" {
  value = module.backend.private_ip
}

output "frontend_private_ip" {
  value = module.frontend.private_ip
}

output "rds_endpoint" {
  value = module.rds.endpoint
}
