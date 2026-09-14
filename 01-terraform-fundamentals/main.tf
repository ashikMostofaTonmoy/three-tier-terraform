# Terraform's job: describe the END STATE you want, not the steps to get
# there. This whole file says "one Ubuntu 24.04 EC2 instance should exist" —
# nothing about *how* AWS creates it. Compare with infra/01-ec2.sh in the
# three-tier-deployment repo, which is a step-by-step IMPERATIVE script doing
# the same underlying job (launch one instance) — that's the whole
# declarative-vs-imperative distinction, made concrete.

# A "data source" reads something that ALREADY exists in AWS — it creates
# nothing itself. This one finds the most recently published Ubuntu 24.04
# AMI from Canonical's own account, so the AMI ID is never hardcoded (and
# never goes stale as Canonical ships new patch releases).
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# A "resource" is something Terraform WILL create, update, or destroy to
# match this description. No security group is attached on purpose — this
# lesson is about the workflow (init/plan/apply/destroy), not connectivity.
resource "aws_instance" "first" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  tags = {
    Name      = "three-tier-terraform-01-first-ec2"
    ManagedBy = "terraform"
    Lesson    = "01-terraform-fundamentals"
  }
}
