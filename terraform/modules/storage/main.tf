# --- Raw events bucket (Firehose S3 destination + COPY staging) ------------
resource "aws_s3_bucket" "raw" {
  bucket        = "${var.name_prefix}-raw-${var.account_id}"
  force_destroy = true # demo: allow terraform destroy to empty the bucket
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    id     = "expire-raw"
    status = "Enabled"
    filter {}
    expiration {
      days = var.raw_expiration_days
    }
  }
}

# --- Errors bucket (Firehose failed-delivery destination) ------------------
resource "aws_s3_bucket" "errors" {
  bucket        = "${var.name_prefix}-errors-${var.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "errors" {
  bucket = aws_s3_bucket.errors.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "errors" {
  bucket                  = aws_s3_bucket.errors.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "errors" {
  bucket = aws_s3_bucket.errors.id
  rule {
    id     = "expire-errors"
    status = "Enabled"
    filter {}
    expiration {
      days = var.errors_expiration_days
    }
  }
}

# --- DynamoDB click-counts table (fraud detection state) -------------------
resource "aws_dynamodb_table" "click_counts" {
  name         = "${var.name_prefix}-click-counts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }
  attribute {
    name = "sk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
