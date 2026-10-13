provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
      Env       = "demo"
    }
  }
}

# awscc provider shares the same region/profile via the standard AWS credential chain.
provider "awscc" {
  region  = var.region
  profile = var.aws_profile
}
