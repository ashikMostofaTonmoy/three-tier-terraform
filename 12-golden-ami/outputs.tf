output "ami_id" {
  value = aws_ami_from_instance.runtime.id
}

output "ami_name" {
  value = aws_ami_from_instance.runtime.name
}

output "builder_instance_id" {
  value = module.builder.instance_id
}
