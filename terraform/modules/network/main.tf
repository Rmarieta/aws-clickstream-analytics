data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Use exactly 2 AZs for cost optimization.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# --- Public subnets (one per AZ) -------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name_prefix}-public-${local.azs[count.index]}" }
}

# --- Private subnets (one per AZ, for Redshift) ----------------------------
resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index + 8)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name_prefix}-private-${local.azs[count.index]}" }
}

# --- Internet gateway + public routing -------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private route table (no NAT gateway — Redshift needs no internet) ------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- S3 Gateway VPC endpoint (free; keeps S3 traffic off the internet) ------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}

# --- Security groups --------------------------------------------------------
# Lambda SG (fraud detector). No inbound; all outbound (DynamoDB/SNS/CW public
# endpoints). The fraud Lambda is not VPC-attached in this design, but the SG
# exists so Redshift's SG can reference it as an allowed source.
resource "aws_security_group" "lambda" {
  name        = "${var.name_prefix}-lambda-sg"
  description = "Lambda fraud detector"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-lambda-sg" }
}

# Redshift SG: inbound 5439 from the Lambda SG and from an optional QuickSight
# CIDR (documented manual step — left as a variable, empty disables the rule).
resource "aws_security_group" "redshift" {
  name        = "${var.name_prefix}-redshift-sg"
  description = "Redshift Serverless"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-redshift-sg" }
}

resource "aws_security_group_rule" "redshift_from_lambda" {
  type                     = "ingress"
  from_port                = 5439
  to_port                  = 5439
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redshift.id
  source_security_group_id = aws_security_group.lambda.id
  description              = "Redshift access from Lambda SG"
}

resource "aws_security_group_rule" "redshift_from_quicksight" {
  count             = var.quicksight_cidr == "" ? 0 : 1
  type              = "ingress"
  from_port         = 5439
  to_port           = 5439
  protocol          = "tcp"
  security_group_id = aws_security_group.redshift.id
  cidr_blocks       = [var.quicksight_cidr]
  description       = "Redshift access from QuickSight CIDR (manual step)"
}
