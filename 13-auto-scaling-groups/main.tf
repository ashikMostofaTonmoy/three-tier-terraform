data "aws_caller_identity" "current" {}

# The runtime image baked in lesson 12 — found by tag, not hardcoded ID, so
# re-baking a v2 image is picked up automatically on the next apply (and
# triggers an instance refresh, since the launch template changes).
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
  name   = "three-tier-terraform-13"
}

# --- Security groups. One rule moved compared to lessons 09-11: the
# backend now accepts 3000 from the ALB, not from the frontend — the ALB
# routes /api/* straight to the backend fleet (see modules/alb-path-routing).
resource "aws_security_group" "alb" {
  name        = "three-tier-terraform-13-alb-sg"
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

  tags = { Lesson = "13-auto-scaling-groups", Tier = "alb" }
}

resource "aws_security_group" "frontend" {
  name        = "three-tier-terraform-13-frontend-sg"
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

  tags = { Lesson = "13-auto-scaling-groups", Tier = "frontend" }
}

resource "aws_security_group" "backend" {
  name        = "three-tier-terraform-13-backend-sg"
  description = "App port from the ALB only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "App port from the ALB (path rule /api/*, /health)"
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

  tags = { Lesson = "13-auto-scaling-groups", Tier = "backend" }
}

resource "aws_security_group" "db" {
  name        = "three-tier-terraform-13-db-sg"
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

  tags = { Lesson = "13-auto-scaling-groups", Tier = "db" }
}

module "db_secret" {
  source = "./modules/secrets"
  name   = "three-tier-terraform/13/db-password"
}

module "rds" {
  source             = "./modules/rds"
  identifier         = "three-tier-terraform-13"
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [aws_security_group.db.id]
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = module.db_secret.password
}

# --- App artifacts, same pattern as lessons 05-11. Every instance any ASG
# launches pulls these at boot, so S3 is now the single source of "what
# version is deployed" — in the CodePipeline topic, CodeDeploy replaces this step.
resource "aws_s3_bucket" "artifacts" {
  bucket        = "three-tier-terraform-13-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Lesson = "13-auto-scaling-groups" }
}

resource "null_resource" "frontend_build" {
  triggers = { always = timestamp() }
  provisioner "local-exec" {
    working_dir = "${path.module}/../frontend"
    command     = "npm ci && npm run build"
  }
}

data "archive_file" "frontend_zip" {
  depends_on  = [null_resource.frontend_build]
  type        = "zip"
  source_dir  = "${path.module}/../frontend/dist"
  output_path = "${path.module}/.build/frontend.zip"
}

data "archive_file" "backend_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend"
  output_path = "${path.module}/.build/backend.zip"
  excludes    = ["node_modules", ".env"]
}

resource "aws_s3_object" "frontend" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "frontend.zip"
  source = data.archive_file.frontend_zip.output_path
  etag   = data.archive_file.frontend_zip.output_md5
}

resource "aws_s3_object" "backend" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "backend.zip"
  source = data.archive_file.backend_zip.output_path
  etag   = data.archive_file.backend_zip.output_md5
}

resource "aws_s3_object" "migration" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "migration.sql"
  source = "${path.module}/../database/migrations/001_create_search_history.sql"
  etag   = filemd5("${path.module}/../database/migrations/001_create_search_history.sql")
}

module "app_role" {
  source       = "./modules/iam"
  name         = "three-tier-terraform-13-ec2"
  secret_arns  = [module.db_secret.secret_arn]
  s3_read_arns = ["${aws_s3_bucket.artifacts.arn}/*"]
  enable_ssm   = true
}

module "alb" {
  source             = "./modules/alb-path-routing"
  name               = "three-tier-tf-13"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
}

# --- Backend fleet: both private-app subnets (2 AZs), never fewer than 2
# instances, target tracking keeps average CPU near 50%.
module "backend_asg" {
  source = "./modules/asg"

  name                 = "three-tier-terraform-13-backend"
  ami_id               = data.aws_ami.runtime.id
  instance_type        = var.backend_instance_type
  subnet_ids           = module.vpc.private_app_subnet_ids
  security_group_ids   = [aws_security_group.backend.id]
  iam_instance_profile = module.app_role.instance_profile_name
  target_group_arns    = [module.alb.backend_target_group_arn]
  min_size             = var.backend_min
  max_size             = var.backend_max
  desired_capacity     = var.backend_min
  target_cpu           = 50
  extra_tags           = { Lesson = "13-auto-scaling-groups", Tier = "backend" }

  user_data = templatefile("${path.module}/user_data_backend.sh.tpl", {
    aws_region       = var.aws_region
    app_version      = var.app_version
    db_secret_arn    = module.db_secret.secret_arn
    db_host          = module.rds.address
    db_name          = var.db_name
    db_user          = var.db_user
    artifacts_bucket = aws_s3_bucket.artifacts.id
    backend_key      = aws_s3_object.backend.key
    migration_key    = aws_s3_object.migration.key
  })
}

# --- Frontend fleet (the "optional" one): same module, step scaling
# instead of target tracking so both policy types are on screen at once.
module "frontend_asg" {
  source = "./modules/asg"

  name                 = "three-tier-terraform-13-frontend"
  ami_id               = data.aws_ami.runtime.id
  instance_type        = var.frontend_instance_type
  subnet_ids           = module.vpc.private_app_subnet_ids
  security_group_ids   = [aws_security_group.frontend.id]
  iam_instance_profile = module.app_role.instance_profile_name
  target_group_arns    = [module.alb.frontend_target_group_arn]
  min_size             = var.frontend_min
  max_size             = var.frontend_max
  desired_capacity     = var.frontend_min
  step_scaling         = true
  extra_tags           = { Lesson = "13-auto-scaling-groups", Tier = "frontend" }

  user_data = templatefile("${path.module}/user_data_frontend.sh.tpl", {
    aws_region       = var.aws_region
    app_version      = var.app_version
    artifacts_bucket = aws_s3_bucket.artifacts.id
    frontend_key     = aws_s3_object.frontend.key
  })
}
