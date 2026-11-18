# Terraform and AWS provider versions.
# The exact provider build is pinned in .terraform.lock.hcl (committed).

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x, never a breaking 7.0
    }
  }
}
