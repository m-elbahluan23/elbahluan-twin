# =============================================================================
# backend.tf - WHERE Terraform stores its state
# =============================================================================
# What is "state"?
#   A JSON file in which Terraform remembers which real AWS resources it
#   created (IDs, ARNs, settings). Without it, Terraform would not know what
#   already exists and would try to create everything again.
#
# Where it is stored:
#   In the S3 bucket `twin-terraform-state-<ACCOUNT_ID>` (eu-north-1).
#   The DynamoDB table `twin-terraform-locks` holds a LOCK while a deploy is
#   running, so two deploys can't write the state at the same time.
#   Each environment (dev/test/prod) has its own state file, e.g.
#     env:/dev/dev/terraform.tfstate
#
# Why the block is empty:
#   The bucket name contains the account ID, so the values are passed at
#   `terraform init` time by scripts/deploy.sh / deploy.ps1 / destroy.*:
#     -backend-config="bucket=twin-terraform-state-<ACCOUNT_ID>"
#     -backend-config="key=<env>/terraform.tfstate"
#     -backend-config="region=<region>"
#     -backend-config="dynamodb_table=twin-terraform-locks"
#     -backend-config="encrypt=true"
#
# These two resources are NOT created by this project. They come from the
# one-time "setup" step (see README -> One-time setup). If the bucket is
# deleted, `terraform init` fails with "NoSuchBucket".
#
# Permissions needed (deploy role):
#   - S3       : read/write the state bucket   (AmazonS3FullAccess)
#   - DynamoDB : read/write the lock table     (AmazonDynamoDBFullAccess)
#
# Cost: practically $0 (a few KB in S3, on-demand DynamoDB).
# =============================================================================

terraform {
  backend "s3" {
    # These values will be set by deployment scripts
    # For local development, they can be passed via -backend-config
  }
}
