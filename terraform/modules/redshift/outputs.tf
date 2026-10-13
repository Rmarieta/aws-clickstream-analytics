output "workgroup_name" {
  value = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_endpoint" {
  value = aws_redshiftserverless_workgroup.this.endpoint[0].address
}

output "namespace_name" {
  value = aws_redshiftserverless_namespace.this.namespace_name
}

output "namespace_arn" {
  value = aws_redshiftserverless_namespace.this.arn
}

output "database" {
  value = var.database
}

output "secret_arn" {
  value     = aws_secretsmanager_secret.redshift.arn
  sensitive = true
}

output "admin_password" {
  description = "Redshift admin password — consumed by the Firehose Redshift destination."
  value       = random_password.admin.result
  sensitive   = true
}

output "s3_copy_role_arn" {
  value = aws_iam_role.redshift_s3.arn
}

output "streaming_role_arn" {
  description = "IAM role ARN for Kinesis Streaming Ingestion (use in CREATE EXTERNAL SCHEMA)."
  value       = aws_iam_role.redshift_streaming.arn
}
