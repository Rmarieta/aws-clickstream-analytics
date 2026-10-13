data "aws_caller_identity" "current" {}

# ===========================================================================
# Kinesis Data Stream (on-demand, single ingestion point)
# ===========================================================================
resource "aws_kinesis_stream" "events" {
  name             = "${var.name_prefix}-events"
  retention_period = var.retention_hours

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"
}

# ===========================================================================
# Firehose transform Lambda (optional enrichment)
# ===========================================================================
data "archive_file" "transform" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/firehose-transform"
  output_path = "${path.module}/build/firehose-transform.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "transform" {
  name               = "${var.name_prefix}-firehose-transform"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "transform_logs" {
  role       = aws_iam_role.transform.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "transform" {
  function_name    = "${var.name_prefix}-firehose-transform"
  role             = aws_iam_role.transform.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.transform.output_path
  source_code_hash = data.archive_file.transform.output_base64sha256
  memory_size      = 256
  timeout          = 60
}

# ===========================================================================
# Firehose delivery role (S3-only, no Redshift)
# ===========================================================================
data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.name_prefix}-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

data "aws_iam_policy_document" "firehose" {
  # Read the source Kinesis stream.
  statement {
    sid = "KinesisRead"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
    ]
    resources = [aws_kinesis_stream.events.arn]
  }

  # Write to S3 data lake bucket.
  statement {
    sid = "S3Write"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
      var.errors_bucket_arn,
      "${var.errors_bucket_arn}/*",
    ]
  }

  # Invoke the transform Lambda.
  statement {
    sid     = "LambdaInvoke"
    actions = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
    resources = [
      aws_lambda_function.transform.arn,
      "${aws_lambda_function.transform.arn}:*",
    ]
  }

  # Glue Data Catalog access for Parquet schema (format conversion).
  statement {
    sid = "GlueAccess"
    actions = [
      "glue:GetTable",
      "glue:GetTableVersion",
      "glue:GetTableVersions",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
      "arn:aws:glue:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/${var.glue_table_name}",
    ]
  }

  # CloudWatch log delivery.
  statement {
    sid     = "Logs"
    actions = ["logs:PutLogEvents", "logs:CreateLogStream", "logs:CreateLogGroup"]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/*",
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "delivery"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

# CloudWatch log group for Firehose delivery diagnostics.
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.name_prefix}-delivery"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# ===========================================================================
# Firehose delivery stream → S3 (Parquet format for data lake / Athena)
#
# This is the DATA LAKE path. Real-time analytics goes through Redshift
# Streaming Ingestion (configured separately via SQL external schema).
# ===========================================================================
resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = "${var.name_prefix}-delivery"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.events.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.raw_bucket_arn

    # Hive-style partitioning for efficient Athena queries
    prefix              = "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"

    # Buffer settings (60s or 64MB, whichever first)
    buffering_size     = 64
    buffering_interval = 60

    # Parquet format via Glue Data Catalog schema
    data_format_conversion_configuration {
      enabled = true

      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = "SNAPPY"
          }
        }
      }

      schema_configuration {
        database_name = var.glue_database_name
        table_name    = var.glue_table_name
        role_arn      = aws_iam_role.firehose.arn
        region        = var.region
      }
    }

    # Optional Lambda transform for enrichment
    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.transform.arn}:$LATEST"
        }
      }
    }

    # CloudWatch logging
    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3.name
    }
  }
}
