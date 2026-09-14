output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "frontend_private_ip" {
  value = module.frontend.private_ip
}

output "backend_private_ip" {
  value = module.backend.private_ip
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "app_url" {
  value = "http://${module.alb.dns_name}"
}

output "ssh_key_file" {
  value = local_file.private_key.filename
}
