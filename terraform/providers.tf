# =============================================================================
# providers.tf - HOW Terraform connects to AWS
# =============================================================================
# What this file does:
#   Configures the AWS provider (the plugin that talks to the AWS APIs).
#   Two configurations are defined:
#     1. The default one  -> used by almost every resource (your main region).
#     2. "us_east_1" alias -> used ONLY for the custom-domain SSL certificate,
#        because CloudFront only accepts certificates created in us-east-1.
#
# Where the credentials come from:
#   - Locally : your AWS CLI profile (`aws configure`), user "aiengineer".
#   - In CI   : GitHub Actions assumes the IAM role `github-actions-twin-deploy`
#               through OIDC (no stored keys). See .github/workflows/deploy.yml.
#
# Which region:
#   The default provider has no `region` here, so it uses the AWS_REGION /
#   AWS_DEFAULT_REGION environment variable or your CLI profile
#   (this project uses eu-north-1).
# =============================================================================

# Default provider: everything is created in your main region (eu-north-1).
provider "aws" {
  # Uses AWS CLI configuration (aws configure)
}

# Second provider pinned to us-east-1.
# Used with `provider = aws.us_east_1` in domain.tf for the ACM certificate.
# Only does anything when use_custom_domain = true.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
