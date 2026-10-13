resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "ClickstreamAnalytics"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "Kinesis — Incoming",
          region = var.region,
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", "StreamName", var.stream_name, { stat = "Sum" }],
            ["AWS/Kinesis", "IncomingBytes", "StreamName", var.stream_name, { stat = "Sum" }],
          ],
          period = 60
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Kinesis — Iterator Age",
          region = var.region,
          metrics = [
            ["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", var.stream_name, { stat = "Average" }],
          ],
          period = 60
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "Firehose — S3 Delivery (Data Lake)",
          region = var.region,
          metrics = [
            ["AWS/Firehose", "DeliveryToS3.Success", "DeliveryStreamName", var.delivery_stream_name, { stat = "Sum" }],
            ["AWS/Firehose", "DeliveryToS3.Records", "DeliveryStreamName", var.delivery_stream_name, { stat = "Sum" }],
            ["AWS/Firehose", "DeliveryToS3.Bytes", "DeliveryStreamName", var.delivery_stream_name, { stat = "Sum" }],
          ],
          period = 60
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "Lambda — Fraud Detector",
          region = var.region,
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.fraud_function_name, { stat = "Sum" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.fraud_function_name, { stat = "Sum" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.fraud_function_name, { stat = "Average" }],
          ],
          period = 60
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6,
        properties = {
          title  = "Custom — Clickstream Analytics",
          region = var.region,
          metrics = [
            ["ClickstreamAnalytics", "FraudAlertsTriggered", { stat = "Sum" }],
            ["ClickstreamAnalytics", "EventsProcessed", { stat = "Sum" }],
            ["ClickstreamAnalytics", "DetectionLatencyMs", { stat = "Average" }],
          ],
          period = 60
        }
      },
    ]
  })
}

# ===========================================================================
# ALARMS
# ===========================================================================

# ---------------------------------------------------------------------------
# Iterator Age Alarm — GATED ON ACTIVE INGESTION
#
# This uses CloudWatch Metric Math to only alarm when BOTH conditions are true:
# 1. Iterator age > 60 seconds (consumer falling behind)
# 2. IncomingRecords > 0 (stream is actively receiving data)
#
# This prevents false alarms on idle streams where stale shard references
# can report high iterator ages even with no data flowing.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  alarm_name          = "${var.name_prefix}-kinesis-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 1  # The metric math expression returns 1 when alarming

  alarm_description = "Kinesis consumer lag >60s while stream is actively receiving data (sustained 15 min)."

  # Metric math: alarm only when iterator age is high AND there's incoming data
  metric_query {
    id          = "e1"
    expression  = "IF(m1 > 60000 AND m2 > 0, 1, 0)"
    label       = "IteratorAgeDuringActiveIngestion"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "GetRecords.IteratorAgeMilliseconds"
      namespace   = "AWS/Kinesis"
      period      = 300
      stat        = "Maximum"
      dimensions  = { StreamName = var.stream_name }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "IncomingRecords"
      namespace   = "AWS/Kinesis"
      period      = 300
      stat        = "Sum"
      dimensions  = { StreamName = var.stream_name }
    }
  }

  alarm_actions      = [var.alerts_topic_arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Fraud detector Lambda error count > 5 in 5 minutes."
  dimensions          = { FunctionName = var.fraud_function_name }
  alarm_actions       = [var.alerts_topic_arn]
  treat_missing_data  = "notBreaching"
}

# Firehose S3 delivery alarm (no more Redshift destination)
resource "aws_cloudwatch_metric_alarm" "firehose_failures" {
  alarm_name          = "${var.name_prefix}-firehose-s3-failures"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeliveryToS3.Success"
  namespace           = "AWS/Firehose"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Firehose S3 delivery success rate dropped below 100%."
  dimensions          = { DeliveryStreamName = var.delivery_stream_name }
  alarm_actions       = [var.alerts_topic_arn]
  treat_missing_data  = "notBreaching"
}
