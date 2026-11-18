# Remote state in S3 (twin-terraform-state-<ACCOUNT_ID>) with a DynamoDB lock
# (twin-terraform-locks). Both come from the one-time setup, not this config.
# Values are passed at `terraform init` by scripts/deploy.* and destroy.*,
# because the bucket name contains the account ID.

terraform {
  backend "s3" {}
}
