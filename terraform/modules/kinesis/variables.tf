variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "retention_hours" {
  type    = number
  default = 24
}

variable "raw_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket for data lake storage."
}

variable "errors_bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket for Firehose error output."
}

# Glue Data Catalog references for Parquet format conversion
variable "glue_database_name" {
  type        = string
  description = "Name of the Glue database containing the events table schema."
}

variable "glue_table_name" {
  type        = string
  description = "Name of the Glue table with the schema for Parquet conversion."
}
