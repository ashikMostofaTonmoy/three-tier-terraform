# random_password's result is NOT encrypted in Terraform state — anyone
# with read access to state can recover it (see lesson 03's `sensitive`
# discussion). This is fine here because state itself lives in an
# encrypted, access-controlled S3 bucket (lesson 04) — the real security
# boundary is around the state file, not this resource.
resource "random_password" "this" {
  length  = var.password_length
  special = true
  # Excludes characters that break either a postgresql:// connection string
  # (@ : / \) or naive shell interpolation in user_data (" ' $ ` space).
  override_special = "!#%^*()-_=+"
}

resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  recovery_window_in_days = 0 # immediate delete on destroy — a lab, not prod

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = random_password.this.result

  # Without this, a later `apply` that touches unrelated resources could
  # regenerate random_password's value (if its arguments ever changed) and
  # silently rotate the password out from under a running app.
  lifecycle {
    ignore_changes = [secret_string]
  }
}
