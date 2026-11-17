# =============================================================================
# terraform.tf - Terraform & provider VERSION requirements
# =============================================================================
# What this file does:
#   Pins which Terraform CLI version and which AWS provider (plugin) version
#   this project works with. `terraform init` reads this to download the
#   right AWS provider.
#
# Related file:
#   .terraform.lock.hcl records the EXACT provider version that was chosen
#   (e.g. 6.73.0) plus checksums, so CI and your laptop use the same build.
#   That lock file is committed to git on purpose.
#
# Permissions needed: none (this is local configuration only).
# =============================================================================

terraform {
  # Any Terraform CLI 1.x or newer is accepted.
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "~> 6.0" = any 6.x version (6.0, 6.73, ...) but NOT 7.0,
      # so a future major version with breaking changes is never picked up.
      version = "~> 6.0"
    }
  }
}
