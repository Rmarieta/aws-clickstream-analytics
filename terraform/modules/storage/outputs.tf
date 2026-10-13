output "raw_bucket_name" {
  value = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  value = aws_s3_bucket.raw.arn
}

output "errors_bucket_name" {
  value = aws_s3_bucket.errors.id
}

output "errors_bucket_arn" {
  value = aws_s3_bucket.errors.arn
}

output "click_counts_table_name" {
  value = aws_dynamodb_table.click_counts.name
}

output "click_counts_table_arn" {
  value = aws_dynamodb_table.click_counts.arn
}
