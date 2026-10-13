output "vpc_connection_id" {
  description = "The QuickSight VPC connection id (select this when creating the Redshift data source)."
  value       = aws_quicksight_vpc_connection.this.vpc_connection_id
}

output "vpc_connection_arn" {
  description = "ARN of the QuickSight VPC connection."
  value       = aws_quicksight_vpc_connection.this.arn
}

output "security_group_id" {
  description = "Security group id attached to the QuickSight ENIs."
  value       = aws_security_group.quicksight.id
}

output "execution_role_arn" {
  description = "IAM role ARN QuickSight assumes to manage the VPC-connection ENIs."
  value       = aws_iam_role.quicksight_vpc.arn
}
