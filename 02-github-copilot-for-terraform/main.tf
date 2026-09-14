# This file is written the way a student actually would with Copilot: a
# comment stating intent, then accepting/editing the suggestion. The full
# before/after transcript for each block is in README.md — read that first.

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

# Prompt given to Copilot: "security group allowing SSH from my IP and HTTP
# from anywhere, for a single EC2 instance"
# Copilot's first suggestion opened SSH to 0.0.0.0/0 — rejected, see README.
resource "aws_security_group" "web" {
  name        = "three-tier-terraform-02-web-sg"
  description = "Allow SSH from my IP and HTTP from anywhere"

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name   = "three-tier-terraform-02-web-sg"
    Lesson = "02-github-copilot-for-terraform"
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.web.id]

  tags = {
    Name      = "three-tier-terraform-02-copilot-ec2"
    ManagedBy = "terraform"
    Lesson    = "02-github-copilot-for-terraform"
  }
}
