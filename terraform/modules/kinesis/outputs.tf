output "stream_name" {
  value = aws_kinesis_stream.events.name
}

output "stream_arn" {
  value = aws_kinesis_stream.events.arn
}

output "delivery_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.this.name
}

output "delivery_stream_arn" {
  value = aws_kinesis_firehose_delivery_stream.this.arn
}

output "transform_function_name" {
  value = aws_lambda_function.transform.function_name
}
