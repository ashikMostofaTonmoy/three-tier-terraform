output "asg_name" {
  value = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  value = aws_launch_template.this.id
}

output "launch_template_version" {
  value = aws_launch_template.this.latest_version
}
