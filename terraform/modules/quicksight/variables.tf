variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'clickstream')."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the QuickSight ENIs are placed."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs (same subnets as Redshift) for the QuickSight VPC connection ENIs. Must span >=2 AZs."
  type        = list(string)
}

variable "redshift_sg_id" {
  description = "Security group ID of the Redshift workgroup — an inbound 5439 rule from QuickSight is added to it."
  type        = string
}
