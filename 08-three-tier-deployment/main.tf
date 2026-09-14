data "aws_caller_identity" "current" {}

module "vpc" {
  source = "./modules/vpc"
  name   = "three-tier-terraform-08"
}

# --- Security groups, staged to match THIS lesson's architecture exactly:
# frontend is still public (Part 5 stage — lesson 09 moves it behind an ALB
# and private, matching Part 6). No cidr_blocks anywhere except the
# frontend's deliberate public 80.
resource "aws_security_group" "frontend" {
  name        = "three-tier-terraform-08-frontend-sg"
  description = "HTTP from anywhere (still public - see lesson 09)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP"
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

  tags = { Lesson = "08-three-tier-deployment", Tier = "frontend" }
}

resource "aws_security_group" "backend" {
  name        = "three-tier-terraform-08-backend-sg"
  description = "App port from the frontend only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "App port from the frontend"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Lesson = "08-three-tier-deployment", Tier = "backend" }
}

resource "aws_security_group" "db" {
  name        = "three-tier-terraform-08-db-sg"
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

  tags = { Lesson = "08-three-tier-deployment", Tier = "db" }
}

module "db_secret" {
  source = "./modules/secrets"
  name   = "three-tier-terraform/08/db-password"
}

module "rds" {
  source             = "./modules/rds"
  identifier         = "three-tier-terraform-08"
  subnet_ids         = module.vpc.private_db_subnet_ids
  security_group_ids = [aws_security_group.db.id]
  db_name            = var.db_name
  db_user            = var.db_user
  db_password        = module.db_secret.password
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "three-tier-terraform-08-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Lesson = "08-three-tier-deployment" }
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
  name         = "three-tier-terraform-08-ec2"
  secret_arns  = [module.db_secret.secret_arn]
  s3_read_arns = ["${aws_s3_bucket.artifacts.arn}/*"]
  enable_ssm   = true
}

module "backend" {
  source = "./modules/ec2"

  name                 = "three-tier-terraform-08-backend"
  instance_type        = var.backend_instance_type
  subnet_id            = module.vpc.private_app_subnet_ids[0]
  security_group_ids   = [aws_security_group.backend.id]
  iam_instance_profile = module.app_role.instance_profile_name
  associate_public_ip  = false
  extra_tags           = { Lesson = "08-three-tier-deployment", Tier = "backend" }

  user_data = templatefile("${path.module}/user_data_backend.sh.tpl", {
    aws_region       = var.aws_region
    db_secret_arn    = module.db_secret.secret_arn
    db_host          = module.rds.address
    db_name          = var.db_name
    db_user          = var.db_user
    artifacts_bucket = aws_s3_bucket.artifacts.id
    backend_key      = aws_s3_object.backend.key
    migration_key    = aws_s3_object.migration.key
  })
}

module "frontend" {
  source = "./modules/ec2"

  name                 = "three-tier-terraform-08-frontend"
  instance_type        = var.frontend_instance_type
  subnet_id            = module.vpc.public_subnet_ids[0]
  security_group_ids   = [aws_security_group.frontend.id]
  iam_instance_profile = module.app_role.instance_profile_name
  associate_public_ip  = true
  extra_tags           = { Lesson = "08-three-tier-deployment", Tier = "frontend" }

  user_data = templatefile("${path.module}/user_data_frontend.sh.tpl", {
    aws_region         = var.aws_region
    artifacts_bucket   = aws_s3_bucket.artifacts.id
    frontend_key       = aws_s3_object.frontend.key
    backend_private_ip = module.backend.private_ip
  })
}
