output "endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "host only"
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}
