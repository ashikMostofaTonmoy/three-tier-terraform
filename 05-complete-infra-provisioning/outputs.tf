output "instance_id" {
  value = module.app.instance_id
}

output "public_ip" {
  value = module.app.public_ip
}

output "app_url" {
  value = "http://${module.app.public_ip}"
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "db_secret_arn" {
  value = module.db_secret.secret_arn
}
