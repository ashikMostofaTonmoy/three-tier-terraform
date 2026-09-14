# Recreates three-tier-deployment's Part 5/6 SG chain
# (infra/42-security-groups.sh) as Terraform resources: ALB -> frontend ->
# backend -> db, each one only reachable from the tier immediately in front
# of it. No security group in this chain has a port-22-from-0.0.0.0/0 rule —
# the bastion group is the only one with any SSH rule at all, and it's
# scoped to one IP.

# `vpc_id` is a required input, not a null-defaulted lookup done inside
# this module. An earlier version used `count = var.vpc_id == null ? 1 : 0`
# on a `data "aws_vpc" "default"` block to fall back to the default VPC —
# that works fine when vpc_id is a literal null (lesson 07's standalone
# demo), but breaks the moment a caller passes a VPC ID that doesn't exist
# yet at plan time (lesson 10, passing module.vpc.vpc_id): `count` can't
# depend on a value that's unknown until apply, and Terraform refuses with
# "Invalid count argument." Moving the default-VPC fallback to the CALLER
# (see lesson 07's own main.tf) avoids the problem entirely.
locals {
  vpc_id = var.vpc_id
}

# --- ALB: the only group open to the whole internet, and only on 80.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public HTTP entry point"
  vpc_id      = local.vpc_id

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

  tags = { Name = "${var.name_prefix}-alb-sg", Tier = "alb" }
}

# --- Bastion: the only group with an SSH rule, scoped to one IP. Not used
# until lesson 10, defined here because this lesson's job is the whole
# chain, not just the tiers that happen to be built already.
resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "SSH from one operator IP only"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-bastion-sg", Tier = "bastion" }
}

# --- Frontend: reachable on 80 from the ALB only; SSH from the bastion
# only (for lesson 10's ProxyJump, not the open internet).
resource "aws_security_group" "frontend" {
  name        = "${var.name_prefix}-frontend-sg"
  description = "HTTP from the ALB only, SSH from the bastion only"
  vpc_id      = local.vpc_id

  ingress {
    description     = "HTTP from the ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "SSH from the bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-frontend-sg", Tier = "frontend" }
}

# --- Backend: reachable on 3000 from the frontend only (Nginx on the
# frontend proxies /api/ to it over the private network) — never directly
# from the ALB.
resource "aws_security_group" "backend" {
  name        = "${var.name_prefix}-backend-sg"
  description = "App port from the frontend only, SSH from the bastion only"
  vpc_id      = local.vpc_id

  ingress {
    description     = "App port from the frontend"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }

  ingress {
    description     = "SSH from the bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-backend-sg", Tier = "backend" }
}

# --- DB: reachable on 5432 from the backend only. Nothing else in the
# chain — not the frontend, not the bastion — can reach Postgres directly.
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Postgres from the backend only"
  vpc_id      = local.vpc_id

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

  tags = { Name = "${var.name_prefix}-db-sg", Tier = "db" }
}
