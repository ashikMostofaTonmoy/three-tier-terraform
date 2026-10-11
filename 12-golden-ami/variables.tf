variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "aws_profile" {
  type    = string
  default = "ostad"
}

variable "ami_version" {
  description = "Bump this to bake a new image (e.g. v2 after changing build_ami.sh.tpl). Part of the AMI name, so AWS keeps old versions side by side until you destroy them."
  type        = string
  default     = "v1"
}
