variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI/SDK profile used for auth (from ~/.aws/config)."
  type        = string
  default     = "training"
}

variable "name_prefix" {
  description = "Prefix for all resource names. Also used as the Project tag."
  type        = string
  default     = "clickstream"
}

variable "alert_email" {
  description = "Email address subscribed to the SNS fraud-alerts topic. Set in terraform.tfvars (NOT committed)."
  type        = string
}

variable "event_retention_hours" {
  description = "Kinesis Data Stream retention in hours (>=24 for replay)."
  type        = number
  default     = 24
}

variable "raw_expiration_days" {
  description = "Days before raw S3 objects are deleted (demo cost control)."
  type        = number
  default     = 7
}

variable "errors_expiration_days" {
  description = "Days before error S3 objects are deleted."
  type        = number
  default     = 30
}

variable "redshift_base_rpu" {
  description = "Redshift Serverless base capacity (RPU)."
  type        = number
  default     = 8
}

variable "redshift_max_rpu" {
  description = "Redshift Serverless max capacity (RPU)."
  type        = number
  default     = 32
}

variable "redshift_database" {
  description = "Redshift database name."
  type        = string
  default     = "clickstream"
}

variable "redshift_admin_username" {
  description = "Redshift admin username."
  type        = string
  default     = "admin"
}
