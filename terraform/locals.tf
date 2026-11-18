# Shared values used across files.

locals {
  # Custom domain names for CloudFront; empty when use_custom_domain = false.
  aliases = var.use_custom_domain && var.root_domain != "" ? [
    var.root_domain,
    "www.${var.root_domain}"
  ] : []

  # e.g. "twin-dev" - keeps each environment's resources separate.
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
