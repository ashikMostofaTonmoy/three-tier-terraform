# The module requires vpc_id explicitly (see modules/security-group/main.tf
# for why it can't default to a lookup done inside the module) — this
# lesson demos the chain standalone, so it looks up the default VPC here,
# in the caller, where the value is always known at plan time.
data "aws_vpc" "default" {
  default = true
}

module "sg" {
  source      = "./modules/security-group"
  name_prefix = "three-tier-terraform-07"
  vpc_id      = data.aws_vpc.default.id
  my_ip_cidr  = var.my_ip_cidr
}
