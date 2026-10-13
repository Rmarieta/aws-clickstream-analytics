output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "redshift_sg_id" {
  value = aws_security_group.redshift.id
}

output "lambda_sg_id" {
  value = aws_security_group.lambda.id
}
