variable "name_prefix" {
  type = string
}

variable "database" {
  type    = string
  default = "clickstream"
}

variable "admin_username" {
  type    = string
  default = "admin"
}

variable "base_rpu" {
  type    = number
  default = 8
}

variable "max_rpu" {
  type    = number
  default = 32
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "redshift_sg_id" {
  type = string
}

variable "raw_bucket_arn" {
  description = "ARN of the S3 bucket for backup/COPY operations."
  type        = string
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream for Streaming Ingestion."
  type        = string
}
