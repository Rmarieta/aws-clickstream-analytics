# --- Admin password → Secrets Manager (never a variable default) -----------
resource "random_password" "admin" {
  length  = 24
  special = true
  # Redshift disallows a few characters in the admin password.
  override_special = "!#$%&*()-_=+[]{}"
}

resource "aws_secretsmanager_secret" "redshift" {
  name        = "${var.name_prefix}-redshift-admin"
  description = "Redshift Serverless admin credentials for ${var.name_prefix}"
}

resource "aws_secretsmanager_secret_version" "redshift" {
  secret_id = aws_secretsmanager_secret.redshift.id
  secret_string = jsonencode({
    username = var.admin_username
    password = random_password.admin.result
  })
}

# --- IAM role assume policy (shared by both roles) --------------------------
data "aws_iam_policy_document" "redshift_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
  }
}

# ===========================================================================
# IAM Role 1: S3 access (for backup/future COPY operations)
# ===========================================================================
resource "aws_iam_role" "redshift_s3" {
  name               = "${var.name_prefix}-redshift-s3"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume.json
}

data "aws_iam_policy_document" "redshift_s3" {
  statement {
    sid     = "ReadStagingBucket"
    actions = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "redshift_s3" {
  name   = "s3-access"
  role   = aws_iam_role.redshift_s3.id
  policy = data.aws_iam_policy_document.redshift_s3.json
}

# ===========================================================================
# IAM Role 2: Kinesis Streaming Ingestion
# Allows Redshift to pull directly from Kinesis Data Streams
# ===========================================================================
resource "aws_iam_role" "redshift_streaming" {
  name               = "${var.name_prefix}-redshift-streaming"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume.json
}

data "aws_iam_policy_document" "redshift_streaming" {
  statement {
    sid = "KinesisStreamingIngestion"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
      # Enhanced fan-out (optional but recommended for production)
      "kinesis:DescribeStreamConsumer",
      "kinesis:RegisterStreamConsumer",
      "kinesis:DeregisterStreamConsumer",
      "kinesis:SubscribeToShard",
    ]
    resources = [var.kinesis_stream_arn]
  }
}

resource "aws_iam_role_policy" "redshift_streaming" {
  name   = "kinesis-streaming-ingestion"
  role   = aws_iam_role.redshift_streaming.id
  policy = data.aws_iam_policy_document.redshift_streaming.json
}

# --- Redshift Serverless namespace -----------------------------------------
resource "aws_redshiftserverless_namespace" "this" {
  namespace_name      = "${var.name_prefix}-ns"
  db_name             = var.database
  admin_username      = var.admin_username
  admin_user_password = random_password.admin.result
  # Attach both IAM roles
  iam_roles = [
    aws_iam_role.redshift_s3.arn,
    aws_iam_role.redshift_streaming.arn,
  ]
  # Default role for Streaming Ingestion (used when no role specified in SQL)
  default_iam_role_arn = aws_iam_role.redshift_streaming.arn
}

# --- Redshift Serverless workgroup -----------------------------------------
# Note: Redshift Serverless bills per-second only while queries execute and
# idles to zero compute cost automatically — there is no explicit "auto-pause"
# parameter as on provisioned clusters. base_capacity sets the floor per query.
resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name      = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name      = "${var.name_prefix}-wg"
  base_capacity       = var.base_rpu
  max_capacity        = var.max_rpu
  publicly_accessible = false
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.redshift_sg_id]
}
