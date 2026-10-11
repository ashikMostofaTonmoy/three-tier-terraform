output "app_url" {
  value = "http://${module.alb.dns_name}"
}

# Repository variables the blue/green workflow reads. Prefixed BG_ so they
# don't collide with lesson 15's variables in the same repo.
output "github_variables" {
  value = {
    BG_AWS_REGION      = var.aws_region
    BG_AWS_ROLE_ARN    = aws_iam_role.github_deploy.arn
    BG_RELEASES_BUCKET = aws_s3_bucket.releases.id
    BG_BLUE_ASG        = module.backend_asg["blue"].asg_name
    BG_GREEN_ASG       = module.backend_asg["green"].asg_name
    BG_BLUE_TG_ARN     = module.alb.backend_target_group_arns["blue"]
    BG_GREEN_TG_ARN    = module.alb.backend_target_group_arns["green"]
    BG_RULE_ARN        = module.alb.weighted_rule_arn
    BG_FRONTEND_ASG    = module.frontend_asg.asg_name
    BG_APP_URL         = "http://${module.alb.dns_name}"
  }
}
