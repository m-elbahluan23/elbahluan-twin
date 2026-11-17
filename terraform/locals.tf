# =============================================================================
# locals.tf - Shared helper values used by many files
# =============================================================================
# What are locals?
#   Named values computed once and reused everywhere as `local.<name>`.
#   They are NOT inputs (those are in variables.tf) and they don't create
#   anything in AWS. They just avoid repeating the same expression.
#
# Permissions needed: none. Cost: none.
# =============================================================================

locals {
  # Extra domain names (aliases) for CloudFront.
  # - Custom domain ON  -> ["example.com", "www.example.com"]
  # - Custom domain OFF -> [] (site is reachable only on *.cloudfront.net)
  # Used in cloudfront.tf.
  aliases = var.use_custom_domain && var.root_domain != "" ? [
    var.root_domain,
    "www.${var.root_domain}"
  ] : []

  # Prefix for every resource name, e.g. "twin-dev".
  # Keeps dev/test/prod resources separate in the same AWS account.
  name_prefix = "${var.project_name}-${var.environment}"

  # Tags added to every resource that supports tags.
  # Useful in the AWS console / Cost Explorer to filter by project or env.
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
