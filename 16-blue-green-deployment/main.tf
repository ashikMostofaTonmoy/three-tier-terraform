# Same three-tier stack as 15-github-actions-asg, except the backend tier
# exists TWICE — a blue fleet and a green fleet — behind one load balancer
# that sends all user traffic to exactly one of them. See README §2.

data "aws_caller_identity" "current" {}

data "aws_ami" "runtime" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "tag:Name"
    values = ["three-tier-terraform-app-runtime"]
  }
}

locals {
  colors = ["blue", "green"]
}

module "vpc" {
  source = "./modules/vpc"
  name   = "three-tier-terraform-16"
}

resource "aws_security_group" "alb" {
  name        = "three-tier-terraform-16-alb-sg"
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
  name        = "three-tier-terraform-16-frontend-sg"
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

# One backend security group shared by BOTH colors — blue and green are the
# same tier, so they get the same network access (and the same DB access).
resource "aws_security_group" "backend" {
  name        = "three-tier-terraform-16-backend-sg"
  description = "App port from the ALB only (both colors)"
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
  name        = "three-tier-terraform-16-db-sg"
  description = "Postgres from the backend only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Postgres from the backend (both colors)"
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
  name   = "three-tier-terraform/16/db-password"
}

# ONE database for both colors. Blue/green duplicates the stateless tier,
# never the data — which is why schema changes must work for both the old
# and the new release at the same time (README §6).
module "rds" {
  source             = "./modules/rds"
  identifier         = "three-tier-terraform-16"
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [aws_security_group.db.id]
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = module.db_secret.password
}

resource "aws_s3_bucket" "releases" {
  bucket        = "three-tier-terraform-16-releases-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "releases" {
  bucket                  = aws_s3_bucket.releases.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "app_role" {
  source       = "./modules/iam"
  name         = "three-tier-terraform-16-ec2"
  secret_arns  = [module.db_secret.secret_arn]
  s3_read_arns = ["${aws_s3_bucket.releases.arn}/*"]
  enable_ssm   = true
}

module "alb" {
  source             = "./modules/alb-blue-green"
  name               = "three-tier-tf-16"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
  initial_live_color = "blue"
}

# health_check_grace_period = 300. It must stay SHORT: during the grace
# period the ASG ignores load-balancer health, and an instance refresh
# can't start until every instance has left its grace period. The first
# version of this lesson used 1500s so instances could wait for the first
# release — and every deploy within 25 minutes of an instance launching
# stalled at "insufficient data to evaluate its health". Now: instances
# wait up to 4 min for a release (user_data); if none exists yet the boot
# fails, the ASG replaces the instance, and the next one tries again.

# --- The two backend fleets. Identical except for their color: which S3
# pointer they boot from and which target group they register into.
module "backend_asg" {
  source   = "./modules/asg"
  for_each = toset(local.colors)

  name                      = "three-tier-terraform-16-backend-${each.key}"
  ami_id                    = data.aws_ami.runtime.id
  instance_type             = var.backend_instance_type
  subnet_ids                = module.vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.backend.id]
  iam_instance_profile      = module.app_role.instance_profile_name
  target_group_arns         = [module.alb.backend_target_group_arns[each.key]]
  min_size                  = var.backend_per_color
  max_size                  = var.backend_per_color * 2
  desired_capacity          = var.backend_per_color
  health_check_grace_period = 300
  extra_tags                = { Lesson = "16-blue-green-deployment", Tier = "backend", Color = each.key }

  user_data = templatefile("${path.module}/user_data_backend.sh.tpl", {
    color         = each.key
    aws_region    = var.aws_region
    bucket        = aws_s3_bucket.releases.id
    db_secret_arn = module.db_secret.secret_arn
    db_host       = module.rds.address
    db_name       = var.db_name
    db_user       = var.db_user
  })
}

# --- The frontend stays a single fleet updated by rolling replacement (as
# in lesson 15). Static files carry no schema and no API contract, so the
# cost of a second fleet buys nothing here — see README §5.
module "frontend_asg" {
  source = "./modules/asg"

  name                      = "three-tier-terraform-16-frontend"
  ami_id                    = data.aws_ami.runtime.id
  instance_type             = var.frontend_instance_type
  subnet_ids                = module.vpc.private_app_subnet_ids
  security_group_ids        = [aws_security_group.frontend.id]
  iam_instance_profile      = module.app_role.instance_profile_name
  target_group_arns         = [module.alb.frontend_target_group_arn]
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  health_check_grace_period = 300
  extra_tags                = { Lesson = "16-blue-green-deployment", Tier = "frontend" }

  user_data = templatefile("${path.module}/user_data_frontend.sh.tpl", {
    aws_region = var.aws_region
    bucket     = aws_s3_bucket.releases.id
  })
}
