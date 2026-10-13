# --- SNS topic for fraud alerts + email subscription -----------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-fraud-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Fraud detector Lambda --------------------------------------------------
data "archive_file" "fraud" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/fraud-detector"
  output_path = "${path.module}/build/fraud-detector.zip"
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

resource "aws_iam_role" "fraud" {
  name               = "${var.name_prefix}-fraud-detector"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "fraud_logs" {
  role       = aws_iam_role.fraud.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege inline policy: DynamoDB item ops, SNS publish, CW metrics,
# Kinesis read on the source stream.
data "aws_iam_policy_document" "fraud" {
  statement {
    sid       = "DynamoDB"
    actions   = ["dynamodb:UpdateItem", "dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [var.click_counts_table_arn]
  }
  statement {
    sid       = "SNSPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }
  statement {
    sid       = "CloudWatchMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # PutMetricData does not support resource-level scoping
  }
  statement {
    sid = "KinesisRead"
    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetShardIterator",
      "kinesis:GetRecords",
      "kinesis:ListShards",
      "kinesis:ListStreams",
    ]
    resources = [var.stream_arn]
  }
}

resource "aws_iam_role_policy" "fraud" {
  name   = "fraud-detector"
  role   = aws_iam_role.fraud.id
  policy = data.aws_iam_policy_document.fraud.json
}

resource "aws_lambda_function" "fraud" {
  function_name    = "${var.name_prefix}-fraud-detector"
  role             = aws_iam_role.fraud.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.fraud.output_path
  source_code_hash = data.archive_file.fraud.output_base64sha256
  memory_size      = 512
  timeout          = 60

  environment {
    variables = {
      CLICK_COUNTS_TABLE = var.click_counts_table_name
      ALERTS_TOPIC_ARN   = aws_sns_topic.alerts.arn
    }
  }
}

# --- Event source mapping: Kinesis stream → fraud Lambda -------------------
resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn       = var.stream_arn
  function_name          = aws_lambda_function.fraud.arn
  starting_position      = "LATEST"
  batch_size             = 100
  parallelization_factor = 2
  maximum_retry_attempts = 3
}
