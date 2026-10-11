# The whole CI/CD system as code:
#
#   GitHub push ──► CodePipeline ──► CodeBuild ──► CodeDeploy ──► backend ASG
#     (Source)        (orchestrates)   (2 bundles)   (per instance)└► frontend ASG
#
# Nothing here is clicked together in the console except approving the
# GitHub connection once (./github-connection).

data "aws_codestarconnections_connection" "github" {
  name = var.github_connection_name
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "three-tier-terraform-14-pipeline-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# ---------------------------------------------------------------- CodeBuild
resource "aws_iam_role" "codebuild" {
  name = "three-tier-terraform-14-codebuild"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "build"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${aws_s3_bucket.pipeline_artifacts.arn}/*"
      },
    ]
  })
}

resource "aws_codebuild_project" "app" {
  name          = "three-tier-terraform-14-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  source {
    type      = "CODEPIPELINE"
    buildspec = "14-cicd-codepipeline/deploy/buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }
}

# --------------------------------------------------------------- CodeDeploy
resource "aws_iam_role" "codedeploy" {
  name = "three-tier-terraform-14-codedeploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS-managed: lets CodeDeploy find instances by ASG, add its launch
# lifecycle hook to the ASG, and (de)register targets in the ALB.
resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_codedeploy_app" "app" {
  name             = "three-tier-terraform-14"
  compute_platform = "Server"
}

locals {
  deployment_groups = {
    backend = {
      asg          = module.backend_asg.asg_name
      target_group = module.alb.backend_target_group_name
    }
    frontend = {
      asg          = module.frontend_asg.asg_name
      target_group = module.alb.frontend_target_group_name
    }
  }
}

resource "aws_codedeploy_deployment_group" "tier" {
  for_each = local.deployment_groups

  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = each.key
  service_role_arn      = aws_iam_role.codedeploy.arn

  # Attaching the ASG (not instance tags) is what makes "auto-deploy to new
  # instances" work: CodeDeploy installs a lifecycle hook on the ASG, so
  # every instance it launches — scale-out, self-healing, instance refresh
  # — waits in Pending:Wait until the last successful revision is deployed
  # to it, and only then goes InService.
  autoscaling_groups = [each.value.asg]

  # One instance at a time: the rest of the fleet keeps serving.
  deployment_config_name = "CodeDeployDefault.OneAtATime"

  # In-place + traffic control = per instance: deregister from the target
  # group, wait for connections to drain, deploy, validate, re-register.
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  load_balancer_info {
    target_group_info {
      name = each.value.target_group
    }
  }

  # A failed ValidateService anywhere → redeploy the last good revision.
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  # An instance the ASG launched DURING a deployment gets the new revision
  # once the deployment finishes, instead of being left on the old one.
  outdated_instances_strategy = "UPDATE"
}

# ------------------------------------------------------------- CodePipeline
resource "aws_iam_role" "codepipeline" {
  name = "three-tier-terraform-14-codepipeline"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "pipeline"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:GetBucketVersioning", "s3:ListBucket"]
        Resource = [aws_s3_bucket.pipeline_artifacts.arn, "${aws_s3_bucket.pipeline_artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = data.aws_codestarconnections_connection.github.arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.app.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment", "codedeploy:GetDeployment",
          "codedeploy:GetApplication", "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision", "codedeploy:GetDeploymentConfig",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_codepipeline" "app" {
  name          = "three-tier-terraform-14"
  role_arn      = aws_iam_role.codepipeline.arn
  pipeline_type = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]
      configuration = {
        ConnectionArn        = data.aws_codestarconnections_connection.github.arn
        FullRepositoryId     = var.github_repo
        BranchName           = var.github_branch
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["BackendBundle", "FrontendBundle"]
      configuration = {
        ProjectName = aws_codebuild_project.app.name
      }
    }
  }

  # Both tiers deploy in parallel (same run_order); each one is still
  # one-instance-at-a-time inside its own deployment group.
  stage {
    name = "Deploy"
    action {
      name            = "DeployBackend"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["BackendBundle"]
      run_order       = 1
      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.tier["backend"].deployment_group_name
      }
    }
    action {
      name            = "DeployFrontend"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["FrontendBundle"]
      run_order       = 1
      configuration = {
        ApplicationName     = aws_codedeploy_app.app.name
        DeploymentGroupName = aws_codedeploy_deployment_group.tier["frontend"].deployment_group_name
      }
    }
  }

  # Only pushes that touch the app (or how it's deployed) start a run —
  # a README-only commit doesn't redeploy anything.
  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.github_branch]
        }
        file_paths {
          includes = ["frontend/**", "backend/**", "database/**", "14-cicd-codepipeline/deploy/**"]
        }
      }
    }
  }
}
