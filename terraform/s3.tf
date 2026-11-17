# =============================================================================
# s3.tf - The two S3 buckets: chat MEMORY (private) and FRONTEND (public site)
# =============================================================================
# Buckets created (per environment):
#   1. twin-<env>-memory-<ACCOUNT_ID>   -> PRIVATE. Stores conversation history
#                                          (JSON files) written by the Lambda.
#   2. twin-<env>-frontend-<ACCOUNT_ID> -> PUBLIC website. Holds the built
#                                          Next.js files (HTML/JS/CSS), served
#                                          to users through CloudFront.
#
# Who writes into them:
#   - memory   : the Lambda at runtime (permission given in lambda.tf).
#   - frontend : scripts/deploy.sh runs `aws s3 sync frontend/out ...`
#                AFTER terraform apply.
#
# Permissions needed (deploy role, to create/delete these):
#   - s3:* on the buckets (AmazonS3FullAccess attached to the deploy role)
#   - sts:GetCallerIdentity (to read the account ID, inline policy)
#
# On destroy:
#   A bucket can't be deleted while it has files in it, so scripts/destroy.*
#   empties both buckets first, then runs terraform destroy.
#
# Cost: a few cents at most (tiny files, low traffic).
# =============================================================================

# Reads the current AWS account ID (12 digits). Creates nothing.
# Bucket names must be globally unique across ALL AWS customers, so the
# account ID is appended to make them unique.
data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# 1) MEMORY bucket (private)
# -----------------------------------------------------------------------------

# The bucket itself. Used by the Lambda through the S3_BUCKET env variable.
resource "aws_s3_bucket" "memory" {
  bucket = "${local.name_prefix}-memory-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

# Blocks ALL public access - conversations must never be readable from
# the internet. All four switches ON = fully private.
resource "aws_s3_bucket_public_access_block" "memory" {
  bucket = aws_s3_bucket.memory.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disables ACLs (old per-file permission system). The bucket owner (your
# account) owns every object; access is controlled only by IAM policies.
# This is the modern AWS-recommended setting.
resource "aws_s3_bucket_ownership_controls" "memory" {
  bucket = aws_s3_bucket.memory.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# -----------------------------------------------------------------------------
# 2) FRONTEND bucket (public static website)
# -----------------------------------------------------------------------------

# The bucket that holds the website files.
resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

# Turns OFF the "block public access" switches for this bucket ONLY.
# Needed because CloudFront reads the S3 *website endpoint*, which only
# works for public buckets. Without this, the public policy below is rejected.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Enables "static website hosting" on the bucket. This gives the bucket a
# website URL (http://<bucket>.s3-website.<region>.amazonaws.com), which
# CloudFront uses as its origin.
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # Page served for "/" and for folders, e.g. /about/ -> /about/index.html
  index_document {
    suffix = "index.html"
  }

  # Page served when a file doesn't exist.
  error_document {
    key = "404.html"
  }
}

# Bucket policy: lets ANYONE ("*") READ (GetObject) files in this bucket.
# Read-only - nobody on the internet can upload or delete.
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      },
    ]
  })

  # Must wait until public access is unblocked, otherwise AWS rejects a
  # public policy with "AccessDenied".
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}
