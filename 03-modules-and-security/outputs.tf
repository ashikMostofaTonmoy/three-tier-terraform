output "app_a_instance_id" {
  value = module.app_a.instance_id
}

output "app_b_instance_id" {
  value = module.app_b.instance_id
}

# Marking an output sensitive doesn't encrypt it in state — state is still
# plaintext JSON on disk (why lesson 04's remote state uses an encrypted S3
# bucket). It only redacts the CLI's plan/apply/output console display.
output "demo_secret_redacted" {
  value     = var.demo_secret
  sensitive = true
}
