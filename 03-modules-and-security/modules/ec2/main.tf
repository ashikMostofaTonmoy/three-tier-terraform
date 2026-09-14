# A module is just a folder of .tf files that takes inputs (variables.tf)
# and produces outputs (outputs.tf) — the root config below calls this one
# twice (module "app_a" / "app_b") to prove the whole point: write the
# resource shape once, reuse it with different inputs, instead of
# copy-pasting an aws_instance block per server.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "this" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # `null` here means "don't manage this argument — let AWS attach the
  # default security group and leave it alone." An explicit `[]` instead
  # would tell Terraform "this instance should have ZERO security groups,"
  # which AWS's API rejects on every later plan/apply (a real bug hit while
  # building lesson 04: a second `apply` tried to strip AWS's auto-assigned
  # default SG and failed with "VPC-based instances require at least one
  # security group").
  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : null

  # A future apply that changes something forcing recreation (e.g.
  # instance_type on certain families) builds the replacement BEFORE
  # destroying the old one — avoids the gap where neither exists.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    {
      Name      = var.name
      ManagedBy = "terraform"
      Module    = "ec2"
    },
    var.extra_tags
  )
}
