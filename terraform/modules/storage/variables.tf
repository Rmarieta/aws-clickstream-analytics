variable "name_prefix" {
  type = string
}

variable "account_id" {
  description = "AWS account id, used to make S3 bucket names globally unique."
  type        = string
}

variable "raw_expiration_days" {
  type    = number
  default = 7
}

variable "errors_expiration_days" {
  type    = number
  default = 30
}
