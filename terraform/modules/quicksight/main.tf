# ===========================================================================
# QuickSight Module
# ===========================================================================
# Creates the networking + IAM plumbing for Amazon QuickSight to reach the
# private Redshift Serverless workgroup over a VPC connection:
#   - A dedicated security group for the QuickSight ENIs
#   - An inbound rule on the Redshift SG allowing 5439 from that SG
#   - An IAM execution role QuickSight assumes to manage the ENIs
#   - The QuickSight VPC connection itself
#
# NOTE: The QuickSight *account subscription* (Enterprise edition sign-up) is a
# one-time manual step in the console and is NOT managed here. This module only
# provisions the VPC connection that an already-subscribed account uses.
# ===========================================================================

# ---------------------------------------------------------------------------
# Security group for the QuickSight VPC-connection ENIs
# ---------------------------------------------------------------------------
resource "aws_security_group" "quicksight" {
  name        = "${var.name_prefix}-quicksight-sg"
  description = "QuickSight VPC connection ENIs for Redshift access"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-quicksight-sg"
  }
}

# QuickSight requires ALL outbound traffic open on its SG — the ENI needs to
# reach the data source AND return traffic on ephemeral ports. AWS documents
# this explicitly: the QuickSight SG must allow all outbound.
resource "aws_security_group_rule" "quicksight_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.quicksight.id
  description       = "QuickSight ENI outbound (required by QuickSight)"
}

# ---------------------------------------------------------------------------
# Allow QuickSight SG inbound to Redshift on 5439
# ---------------------------------------------------------------------------
resource "aws_security_group_rule" "redshift_from_quicksight" {
  type                     = "ingress"
  from_port                = 5439
  to_port                  = 5439
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.quicksight.id
  security_group_id        = var.redshift_sg_id
  description              = "Redshift access from QuickSight VPC connection"
}

# QuickSight also needs the Redshift SG to allow the return traffic back to the
# QuickSight ENIs on ephemeral ports (stateful SGs usually handle this, but
# QuickSight's cross-ENI model documents an explicit inbound range).
resource "aws_security_group_rule" "redshift_ephemeral_from_quicksight" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.quicksight.id
  security_group_id        = var.redshift_sg_id
  description              = "Return traffic to QuickSight ENIs (ephemeral)"
}

# ---------------------------------------------------------------------------
# IAM execution role QuickSight assumes to manage the VPC-connection ENIs
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["quicksight.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "quicksight_vpc" {
  name               = "${var.name_prefix}-quicksight-vpc"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Minimal permissions QuickSight needs to create/describe/delete the ENIs it
# places in your subnets. This mirrors the AWS-managed policy content.
data "aws_iam_policy_document" "eni" {
  statement {
    sid    = "QuickSightVPCConnectionENIs"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:ModifyNetworkInterfaceAttribute",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "eni" {
  name   = "vpc-connection-enis"
  role   = aws_iam_role.quicksight_vpc.id
  policy = data.aws_iam_policy_document.eni.json
}

# ---------------------------------------------------------------------------
# The QuickSight VPC connection
# ---------------------------------------------------------------------------
resource "aws_quicksight_vpc_connection" "this" {
  vpc_connection_id = "${var.name_prefix}-vpc"
  name              = "${var.name_prefix}-vpc"
  role_arn          = aws_iam_role.quicksight_vpc.arn
  security_group_ids = [aws_security_group.quicksight.id]
  subnet_ids        = var.subnet_ids

  # QuickSight needs the ENI role to exist and the ingress rule in place first.
  depends_on = [
    aws_iam_role_policy.eni,
    aws_security_group_rule.redshift_from_quicksight,
  ]
}
