# Outputs are Terraform's "return values" — printed after apply, and
# readable any time afterward with `terraform output`, without re-running
# anything against AWS.
output "instance_id" {
  description = "The instance ID Terraform created"
  value       = aws_instance.first.id
}

output "ami_id_used" {
  description = "Which AMI the data source actually resolved to"
  value       = data.aws_ami.ubuntu.id
}

output "instance_state" {
  description = "The instance's state at the end of apply"
  value       = aws_instance.first.instance_state
}
