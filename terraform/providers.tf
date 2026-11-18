# AWS connection. Credentials come from your AWS CLI profile locally,
# or from the OIDC role github-actions-twin-deploy in CI.

# Main region (eu-north-1), taken from the AWS_REGION env var / CLI profile.
provider "aws" {
  # Uses AWS CLI configuration (aws configure)
}

# CloudFront only accepts certificates from us-east-1 (used in domain.tf).
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
