# How GitHub Actions gets into AWS with NO stored access keys: the workflow
# asks GitHub for a short-lived OIDC token, AWS checks it was issued for
# THIS repo and an allowed branch, and hands back temporary credentials for
# the role below (valid ~1 hour). Same mechanism three-tier-deployment's
# Part 1 used, now as Terraform.

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Two subject formats exist. Classic: repo:OWNER/REPO:ref:refs/heads/BRANCH.
  # Immutable (newer repos): repo:OWNER@ID/REPO@ID:ref:refs/heads/BRANCH —
  # the IDs stop a deleted-and-recreated repo with the same name from
  # inheriting this trust. Accept classic always, immutable when given.
  sub_prefixes = compact(["repo:${var.github_repo}", var.github_immutable_sub_prefix])
  allowed_subs = flatten([for p in local.sub_prefixes : [for b in var.github_branches : "${p}:ref:refs/heads/${b}"]])
}

resource "aws_iam_role" "github_deploy" {
  name = "three-tier-terraform-15-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # The security boundary: a fork, another repo, or a branch not in
        # this list gets "Not authorized to perform sts:AssumeRoleWithWebIdentity".
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.allowed_subs
        }
      }
    }]
  })
}

# Exactly what the workflow does — publish releases, replace instances,
# watch the refresh — and nothing else. No EC2, no IAM, no Terraform state.
resource "aws_iam_role_policy" "github_deploy" {
  name = "deploy"
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.releases.arn, "${aws_s3_bucket.releases.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = ["autoscaling:StartInstanceRefresh", "autoscaling:CancelInstanceRefresh"]
        Resource = [
          "arn:aws:autoscaling:${var.aws_region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${module.backend_asg.asg_name}",
          "arn:aws:autoscaling:${var.aws_region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${module.frontend_asg.asg_name}",
        ]
      },
      {
        # Describe* calls can't be scoped to one resource in IAM.
        Effect   = "Allow"
        Action   = ["autoscaling:DescribeInstanceRefreshes", "autoscaling:DescribeAutoScalingGroups"]
        Resource = "*"
      },
    ]
  })
}
