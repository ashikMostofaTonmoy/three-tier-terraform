# The shared source-of-truth ec2 module. Lessons 01-04 carry an earlier,
# simpler private copy (no user_data/IAM/subnet inputs — they didn't need
# them yet); lessons 05+ carry copies of THIS version. See each lesson's
# own modules/ec2/ folder — copied, not symlinked, so every lesson stays
# runnable on its own.
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
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip
  iam_instance_profile        = var.iam_instance_profile
  user_data                   = var.user_data
  user_data_replace_on_change = true
  key_name                    = var.key_name

  # `null` (not `[]`) when unset — see the lesson 04 README for the drift
  # bug this avoids: an empty list tells Terraform to actively strip
  # whatever default security group AWS auto-attaches, which AWS's API
  # rejects on every later plan/apply.
  vpc_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : null

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

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
