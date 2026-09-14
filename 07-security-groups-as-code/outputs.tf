output "alb_sg_id" {
  value = module.sg.alb_sg_id
}

output "bastion_sg_id" {
  value = module.sg.bastion_sg_id
}

output "frontend_sg_id" {
  value = module.sg.frontend_sg_id
}

output "backend_sg_id" {
  value = module.sg.backend_sg_id
}

output "db_sg_id" {
  value = module.sg.db_sg_id
}
