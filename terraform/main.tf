# Discover the account id for globally-unique bucket names, so it never has to
# be hardcoded or committed.
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ===========================================================================
# Network (VPC, subnets, security groups)
# ===========================================================================
module "network" {
  source      = "./modules/network"
  name_prefix = var.name_prefix
  region      = var.region
}

# ===========================================================================
# Storage (S3 buckets, DynamoDB)
# ===========================================================================
module "storage" {
  source                 = "./modules/storage"
  name_prefix            = var.name_prefix
  account_id             = local.account_id
  raw_expiration_days    = var.raw_expiration_days
  errors_expiration_days = var.errors_expiration_days
}

# ===========================================================================
# Glue Data Catalog (for Firehose Parquet conversion + Athena queries)
# Must be created before Kinesis module (Firehose needs Glue table reference)
# ===========================================================================
module "glue_catalog" {
  source          = "./modules/glue_catalog"
  name_prefix     = var.name_prefix
  database_name   = "clickstream"
  table_name      = "events"
  raw_bucket_name = module.storage.raw_bucket_name
}

# ===========================================================================
# Kinesis (Data Stream + Firehose → S3 Parquet)
# Creates the stream first, then Firehose delivers to S3 data lake.
# Real-time to Redshift is via Streaming Ingestion (SQL, not Firehose).
# ===========================================================================
module "kinesis" {
  source             = "./modules/kinesis"
  name_prefix        = var.name_prefix
  region             = var.region
  retention_hours    = var.event_retention_hours
  raw_bucket_arn     = module.storage.raw_bucket_arn
  errors_bucket_arn  = module.storage.errors_bucket_arn
  glue_database_name = module.glue_catalog.database_name
  glue_table_name    = module.glue_catalog.table_name
}

# ===========================================================================
# Redshift Serverless (Streaming Ingestion from Kinesis)
# IAM role allows Redshift to pull directly from the Kinesis stream.
# The actual external schema + streaming MV are created via SQL (manual step).
# ===========================================================================
module "redshift" {
  source             = "./modules/redshift"
  name_prefix        = var.name_prefix
  database           = var.redshift_database
  admin_username     = var.redshift_admin_username
  base_rpu           = var.redshift_base_rpu
  max_rpu            = var.redshift_max_rpu
  private_subnet_ids = module.network.private_subnet_ids
  redshift_sg_id     = module.network.redshift_sg_id
  raw_bucket_arn     = module.storage.raw_bucket_arn
  kinesis_stream_arn = module.kinesis.stream_arn
}

# ===========================================================================
# Fraud Detection (Lambda consumer from Kinesis + SNS alerts)
# ===========================================================================
module "fraud_detection" {
  source                  = "./modules/fraud_detection"
  name_prefix             = var.name_prefix
  alert_email             = var.alert_email
  stream_arn              = module.kinesis.stream_arn
  click_counts_table_name = module.storage.click_counts_table_name
  click_counts_table_arn  = module.storage.click_counts_table_arn
}

# ===========================================================================
# Monitoring (CloudWatch dashboard + alarms)
# ===========================================================================
module "monitoring" {
  source               = "./modules/monitoring"
  name_prefix          = var.name_prefix
  region               = var.region
  stream_name          = module.kinesis.stream_name
  delivery_stream_name = module.kinesis.delivery_stream_name
  fraud_function_name  = module.fraud_detection.function_name
  alerts_topic_arn     = module.fraud_detection.topic_arn
}

# ===========================================================================
# QuickSight (VPC connection so QuickSight can reach private Redshift)
# Provisions the SG + IAM execution role + VPC connection. The QuickSight
# account subscription (Enterprise sign-up) is a one-time manual console step.
# ===========================================================================
module "quicksight" {
  source         = "./modules/quicksight"
  name_prefix    = var.name_prefix
  vpc_id         = module.network.vpc_id
  subnet_ids     = module.network.private_subnet_ids
  redshift_sg_id = module.network.redshift_sg_id
}
