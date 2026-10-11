# Infrastructure: the same fleet as 13-auto-scaling-groups (VPC, RDS, ALB
# with path routing, one ASG per tier from the lesson 12 AMI). What changed
# is how the APP gets onto instances — see pipeline.tf and the two
# user_data templates.

data "aws_caller_identity" "current" {}

data "aws_ami" "runtime" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "tag:Name"
    values = ["three-tier-terraform-app-runtime"]
  }
}

module "vpc" {
  source = "./modules/vpc"
  name   = "three-tier-terraform-14"
}

resource "aws_security_group" "alb" {
  name        = "three-tier-terraform-14-alb-sg"
  description = "Public HTTP entry point"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "frontend" {
  name        = "three-tier-terraform-14-frontend-sg"
  description = "HTTP from the ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTP from the ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "backend" {
  name        = "three-tier-terraform-14-backend-sg"
  description = "App port from the ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "App port from the ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "three-tier-terraform-14-db-sg"
  description = "Postgres from the backend only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Postgres from the backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "db_secret" {
  source = "./modules/secrets"
  name   = "three-tier-terraform/14/db-password"
}

module "rds" {
  source             = "./modules/rds"
  identifier         = "three-tier-terraform-14"
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [aws_security_group.db.id]
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = module.db_secret.password
}

# Instances now read revisions from the PIPELINE's artifact bucket (the
# CodeDeploy agent downloads each bundle from there) instead of a bucket
# Terraform filled itself.
module "app_role" {
  source       = "./modules/iam"
  name         = "three-tier-terraform-14-ec2"
  secret_arns  = [module.db_secret.secret_arn]
  s3_read_arns = ["${aws_s3_bucket.pipeline_artifacts.arn}/*"]
  enable_ssm   = true
}

module "alb" {
  source             = "./modules/alb-path-routing"
  name               = "three-tier-tf-14"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
}

# health_check_grace_period is 600s here (180s in lesson 13). A brand-new
# ASG has no app until the pipeline's FIRST run finishes (~6-8 min); with a
# short grace period the ASG would kill every instance as "unhealthy"
# before the first deploy could reach it. See README §2, challenge 1.
module "backend_asg" {
  source = "./modules/asg"

  name                      = "three-tier-terraform-14-backend"
  ami_id                    = data.aws_ami.runtime.id
  instance_type             = var.backend_instance_type
  subnet_ids                = module.vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.backend.id]
  iam_instance_profile      = module.app_role.instance_profile_name
  target_group_arns         = [module.alb.backend_target_group_arn]
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  health_check_grace_period = 600
  target_cpu                = 50
  extra_tags                = { Lesson = "14-cicd-codepipeline", Tier = "backend" }

  user_data = templatefile("${path.module}/user_data_backend.sh.tpl", {
    aws_region    = var.aws_region
    db_secret_arn = module.db_secret.secret_arn
    db_host       = module.rds.address
    db_name       = var.db_name
    db_user       = var.db_user
  })
}

module "frontend_asg" {
  source = "./modules/asg"

  name                      = "three-tier-terraform-14-frontend"
  ami_id                    = data.aws_ami.runtime.id
  instance_type             = var.frontend_instance_type
  subnet_ids                = module.vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.frontend.id]
  iam_instance_profile      = module.app_role.instance_profile_name
  target_group_arns         = [module.alb.frontend_target_group_arn]
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  health_check_grace_period = 600
  step_scaling              = true
  extra_tags                = { Lesson = "14-cicd-codepipeline", Tier = "frontend" }

  user_data = file("${path.module}/user_data_frontend.sh.tpl")
}
