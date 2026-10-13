variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "region" {
  description = "AWS region (for the S3 endpoint service name)."
  type        = string
}

variable "quicksight_cidr" {
  description = "Optional CIDR allowed to reach Redshift on 5439 (QuickSight). Empty disables the rule."
  type        = string
  default     = ""
}
