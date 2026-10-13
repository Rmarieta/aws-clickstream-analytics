output "function_name" {
  value = aws_lambda_function.fraud.function_name
}

output "topic_arn" {
  value = aws_sns_topic.alerts.arn
}
