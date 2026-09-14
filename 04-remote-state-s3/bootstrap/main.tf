# This config's own state stays LOCAL, on purpose — it creates the S3
# bucket and DynamoDB table that every OTHER lesson's remote state depends
# on, so it can't depend on them itself (chicken-and-egg). Run this once,
# note the outputs, then never destroy it until every other lesson is torn
# down (see the root README's ordering warning).

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = "three-tier-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "three-tier-terraform-state"
    Purpose = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = "three-tier-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "three-tier-terraform-lock"
    Purpose = "terraform-state-locking"
  }
}
