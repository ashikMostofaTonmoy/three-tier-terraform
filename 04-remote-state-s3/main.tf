module "app" {
  source = "./modules/ec2"

  name          = "three-tier-terraform-04-remote-state-demo"
  instance_type = "t3.micro"
  extra_tags    = { Lesson = "04-remote-state-s3" }
}
