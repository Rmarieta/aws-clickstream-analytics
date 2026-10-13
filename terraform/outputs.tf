output "stream_name" {
  description = "Kinesis Data Stream name — pass to the simulator with --stream-name."
  value       = module.kinesis.stream_name
}

output "stream_arn" {
  description = "Kinesis Data Stream ARN — used in Redshift Streaming Ingestion external schema."
  value       = module.kinesis.stream_arn
}

output "delivery_stream_name" {
  description = "Firehose delivery stream name (S3 data lake path)."
  value       = module.kinesis.delivery_stream_name
}

output "raw_bucket_name" {
  description = "S3 bucket for data lake (Parquet files from Firehose)."
  value       = module.storage.raw_bucket_name
}

# ---------------------------------------------------------------------------
# Redshift Serverless
# ---------------------------------------------------------------------------
output "redshift_workgroup" {
  value = module.redshift.workgroup_name
}

output "redshift_endpoint" {
  value = module.redshift.workgroup_endpoint
}

output "redshift_database" {
  value = module.redshift.database
}

output "redshift_secret_arn" {
  description = "Secrets Manager ARN holding the Redshift admin credentials."
  value       = module.redshift.secret_arn
  sensitive   = true
}

output "redshift_streaming_role_arn" {
  description = "IAM role ARN for Redshift Streaming Ingestion — use in CREATE EXTERNAL SCHEMA."
  value       = module.redshift.streaming_role_arn
}

# ---------------------------------------------------------------------------
# Glue Data Catalog / Athena (Data Lake)
# ---------------------------------------------------------------------------
output "glue_database_name" {
  description = "Glue database name for Athena queries."
  value       = module.glue_catalog.database_name
}

output "glue_table_name" {
  description = "Glue table name containing clickstream events schema."
  value       = module.glue_catalog.table_name
}

output "athena_workgroup" {
  description = "Athena workgroup name for running queries."
  value       = module.glue_catalog.athena_workgroup_name
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------
output "fraud_alerts_topic_arn" {
  value = module.fraud_detection.topic_arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL."
  value       = module.monitoring.dashboard_url
}

# ---------------------------------------------------------------------------
# QuickSight (VPC connection for private Redshift access)
# ---------------------------------------------------------------------------
output "quicksight_vpc_connection_id" {
  description = "QuickSight VPC connection id — select this when creating the Redshift data source."
  value       = module.quicksight.vpc_connection_id
}

output "quicksight_security_group_id" {
  description = "Security group id attached to the QuickSight ENIs."
  value       = module.quicksight.security_group_id
}

output "quicksight_execution_role_arn" {
  description = "IAM execution role ARN QuickSight uses for the VPC connection."
  value       = module.quicksight.execution_role_arn
}
