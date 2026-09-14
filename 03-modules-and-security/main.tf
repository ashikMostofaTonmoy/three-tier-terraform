# The same module, called twice with different inputs — this is the whole
# lesson. Compare to 01/02's single hand-written aws_instance block: adding
# a third server here is one more `module` block, not another 30 lines of
# duplicated resource config.
module "app_a" {
  source = "./modules/ec2"

  name          = "three-tier-terraform-03-app-a"
  instance_type = "t3.micro"
  extra_tags    = { Lesson = "03-modules-and-security", Role = "app-a" }
}

module "app_b" {
  source = "./modules/ec2"

  name          = "three-tier-terraform-03-app-b"
  instance_type = "t3.micro"
  extra_tags    = { Lesson = "03-modules-and-security", Role = "app-b" }
}
