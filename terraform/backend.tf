# =====================================================================
# STATE BACKEND — S3 remote state with native locking
# ---------------------------------------------------------------------
# This file is PUBLISH-SAFE: it contains no bucket name and no account id.
# The sensitive values (the state bucket name) are supplied at init time
# via a gitignored `backend.hcl` — this is Terraform's "partial backend
# configuration" pattern.
#
# Why partial config? The `backend "s3"` block is read BEFORE variables
# are initialized, so `var.*` cannot be used inside it. Partial config is
# the idiomatic way to keep environment-specific / private values out of
# version control.
#
# Locking: `use_lockfile = true` uses S3-native conditional-write locking
# (Terraform >= 1.11). No DynamoDB lock table is required.
#
# FIRST-TIME SETUP: see the "Remote State" section of the project README.
#   1. Create the state bucket (see README).
#   2. cp backend.hcl.example backend.hcl  and fill in your bucket name.
#   3. terraform init -backend-config=backend.hcl -migrate-state
# =====================================================================

terraform {
  backend "s3" {
    # bucket  -> supplied via backend.hcl (gitignored)
    key          = "clickstream-analytics/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
