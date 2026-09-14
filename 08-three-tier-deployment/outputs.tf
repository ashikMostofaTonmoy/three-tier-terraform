output "frontend_public_ip" {
  value = module.frontend.public_ip
}

output "app_url" {
  value = "http://${module.frontend.public_ip}"
}

output "backend_private_ip" {
  value = module.backend.private_ip
}

output "rds_endpoint" {
  value = module.rds.endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
