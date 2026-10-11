output "app_url" {
  value = "http://${module.alb.dns_name}"
}

output "pipeline_name" {
  value = aws_codepipeline.app.name
}

output "codedeploy_app" {
  value = aws_codedeploy_app.app.name
}

output "backend_asg_name" {
  value = module.backend_asg.asg_name
}

output "frontend_asg_name" {
  value = module.frontend_asg.asg_name
}

output "github_connection_status" {
  description = "Must be AVAILABLE for the pipeline's Source stage to work"
  value       = data.aws_codestarconnections_connection.github.connection_status
}
