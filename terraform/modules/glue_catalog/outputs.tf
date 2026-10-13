output "database_name" {
  value       = aws_glue_catalog_database.this.name
  description = "Name of the Glue database."
}

output "table_name" {
  value       = aws_glue_catalog_table.events.name
  description = "Name of the Glue events table."
}

output "table_arn" {
  value       = aws_glue_catalog_table.events.arn
  description = "ARN of the Glue events table."
}

output "athena_workgroup_name" {
  value       = aws_athena_workgroup.this.name
  description = "Name of the Athena workgroup."
}
