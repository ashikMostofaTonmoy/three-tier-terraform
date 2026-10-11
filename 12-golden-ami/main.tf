# Step 1 — a throwaway "builder" instance in the default VPC (public
# subnet, so it reaches apt/npm/AWS downloads without a NAT Gateway).
module "builder" {
  source = "./modules/ec2"

  name          = "three-tier-terraform-12-ami-builder"
  instance_type = "t3.small"
  extra_tags    = { Lesson = "12-golden-ami", Role = "ami-builder" }

  user_data = templatefile("${path.module}/build_ami.sh.tpl", {
    aws_region  = var.aws_region
    ami_version = var.ami_version
  })
}

# Step 2 — wait for the builder to power itself off (the last line of
# build_ami.sh.tpl). Terraform has no built-in "wait for user_data" — an
# instance reaching `running` says nothing about whether its script is
# done, so snapshotting right after create would capture a half-installed
# image. `aws ec2 wait instance-stopped` polls every 15s, up to 10 minutes.
resource "null_resource" "wait_for_build" {
  triggers = { instance_id = module.builder.instance_id }

  provisioner "local-exec" {
    command = "aws ec2 wait instance-stopped --instance-ids ${module.builder.instance_id} --region ${var.aws_region} --profile ${var.aws_profile}"
  }
}

# Step 3 — snapshot the stopped instance into an AMI. Stopped means the
# filesystem is quiescent, so no reboot is needed for a consistent image.
resource "aws_ami_from_instance" "runtime" {
  name                    = "three-tier-terraform-app-runtime-${var.ami_version}"
  source_instance_id      = module.builder.instance_id
  snapshot_without_reboot = true
  depends_on              = [null_resource.wait_for_build]

  # Default replacement order is destroy-then-create: the old AMI would be
  # deregistered ~12 minutes before the new one exists, while lesson 13's
  # launch templates still point at it — any scale-out or self-healing
  # launch in that window would fail. The name embeds ami_version, so old
  # and new can coexist.
  lifecycle {
    create_before_destroy = true
  }

  # Lesson 13 finds the image by this Name tag, not by ID.
  tags = {
    Name      = "three-tier-terraform-app-runtime"
    Version   = var.ami_version
    ManagedBy = "terraform"
  }
}
