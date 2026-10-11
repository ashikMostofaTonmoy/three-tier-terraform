# Infrastructure: the same fleet as 13-auto-scaling-groups (VPC, RDS, ALB
# with path routing, one ASG per tier from the lesson 12 AMI). No AWS CI/CD
# services at all: GitHub Actions publishes releases to the bucket below and
# replaces instances; see github.tf and .github/workflows/asg-deploy.yml.

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
  name   = "three-tier-terraform-15"
}

resource "aws_security_group" "alb" {
  name        = "three-tier-terraform-15-alb-sg"
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
  name        = "three-tier-terraform-15-frontend-sg"
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
  name        = "three-tier-terraform-15-backend-sg"
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
  name        = "three-tier-terraform-15-db-sg"
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
  name   = "three-tier-terraform/15/db-password"
}

module "rds" {
  source             = "./modules/rds"
  identifier         = "three-tier-terraform-15"
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [aws_security_group.db.id]
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = module.db_secret.password
}

# Releases bucket: GitHub Actions writes releases/<sha>/ and current/;
# instances only ever read current/.
module "app_role" {
  source       = "./modules/iam"
  name         = "three-tier-terraform-15-ec2"
  secret_arns  = [module.db_secret.secret_arn]
  s3_read_arns = ["${aws_s3_bucket.releases.arn}/*"]
  enable_ssm   = true
}

module "alb" {
  source             = "./modules/alb-path-routing"
  name               = "three-tier-tf-15"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
}

# Grace period 1500s: on a brand-new stack, instances wait (up to 20 min, see
# user_data) for the workflow's first release. After that, boots take ~30s.
module "backend_asg" {
  source = "./modules/asg"

  name                      = "three-tier-terraform-15-backend"
  ami_id                    = data.aws_ami.runtime.id
  instance_type             = var.backend_instance_type
  subnet_ids                = module.vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.backend.id]
  iam_instance_profile      = module.app_role.instance_profile_name
  target_group_arns         = [module.alb.backend_target_group_arn]
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  health_check_grace_period = 1500
  target_cpu                = 50
  extra_tags                = { Lesson = "15-github-actions-asg", Tier = "backend" }

  user_data = templatefile("${path.module}/user_data_backend.sh.tpl", {
    aws_region    = var.aws_region
    bucket        = aws_s3_bucket.releases.id
    db_secret_arn = module.db_secret.secret_arn
    db_host       = module.rds.address
    db_name       = var.db_name
    db_user       = var.db_user
  })
}

module "frontend_asg" {
  source = "./modules/asg"

  name                      = "three-tier-terraform-15-frontend"
  ami_id                    = data.aws_ami.runtime.id
  instance_type             = var.frontend_instance_type
  subnet_ids                = module.vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.frontend.id]
  iam_instance_profile      = module.app_role.instance_profile_name
  target_group_arns         = [module.alb.frontend_target_group_arn]
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  health_check_grace_period = 1500
  step_scaling              = true
  extra_tags                = { Lesson = "15-github-actions-asg", Tier = "frontend" }

  user_data = templatefile("${path.module}/user_data_frontend.sh.tpl", {
    aws_region = var.aws_region
    bucket     = aws_s3_bucket.releases.id
  })
}

resource "aws_s3_bucket" "releases" {
  bucket        = "three-tier-terraform-15-releases-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "releases" {
  bucket                  = aws_s3_bucket.releases.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
