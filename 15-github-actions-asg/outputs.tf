output "app_url" {
  value = "http://${module.alb.dns_name}"
}

# The five values the workflow needs. Set them as GitHub repository
# variables (not secrets — none of them is sensitive) with the commands in
# the README, or copy them into Settings → Secrets and variables → Actions.
output "github_variables" {
  value = {
    AWS_REGION      = var.aws_region
    AWS_ROLE_ARN    = aws_iam_role.github_deploy.arn
    RELEASES_BUCKET = aws_s3_bucket.releases.id
    BACKEND_ASG     = module.backend_asg.asg_name
    FRONTEND_ASG    = module.frontend_asg.asg_name
    APP_URL         = "http://${module.alb.dns_name}"
  }
}
