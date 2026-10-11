output "app_url" {
  value = "http://${module.alb.dns_name}"
}

output "runtime_ami_id" {
  value = data.aws_ami.runtime.id
}

output "backend_asg_name" {
  value = module.backend_asg.asg_name
}

output "frontend_asg_name" {
  value = module.frontend_asg.asg_name
}

output "backend_target_group_arn" {
  value = module.alb.backend_target_group_arn
}

output "frontend_target_group_arn" {
  value = module.alb.frontend_target_group_arn
}

output "launch_template_versions" {
  value = {
    backend  = module.backend_asg.launch_template_version
    frontend = module.frontend_asg.launch_template_version
  }
}
