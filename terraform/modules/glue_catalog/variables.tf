variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "database_name" {
  type        = string
  default     = "clickstream"
  description = "Name of the Glue database."
}

variable "table_name" {
  type        = string
  default     = "events"
  description = "Name of the Glue table."
}

variable "raw_bucket_name" {
  type        = string
  description = "Name (not ARN) of the S3 bucket where Parquet data is stored."
}
