resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.identifier}-subnet-group" }
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_user
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids

  # A lab, not prod: RDS requires SSL by default regardless (the backend
  # connects with sslmode=require — see three-tier-deployment's Part 5
  # notes on this), single-AZ keeps cost down, and both flags below mean
  # `terraform destroy` actually removes it instead of leaving a manual
  # snapshot/protection step in the way.
  publicly_accessible = false
  multi_az            = false
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = var.identifier }
}
