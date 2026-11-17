# =============================================================================
# cloudfront.tf - CDN that serves the website over HTTPS
# =============================================================================
# What it does:
#   CloudFront is AWS's global CDN. It sits in front of the frontend S3
#   bucket and:
#     - gives the site an HTTPS URL (https://<id>.cloudfront.net)
#       (the S3 website endpoint itself is HTTP only)
#     - caches files in edge locations worldwide -> faster page loads
#     - optionally serves your own domain (when use_custom_domain = true)
#
# Request flow:
#   Browser --HTTPS--> CloudFront --HTTP--> S3 website endpoint (frontend bucket)
#
# After each deploy, the workflow runs a CloudFront "invalidation" (/*) so
# users get the new files instead of the cached old ones.
#
# Permissions needed (deploy role):
#   - cloudfront:*  (CloudFrontFullAccess)
#
# Notes:
#   - Creating/deleting a distribution takes ~3-5 minutes (normal).
#   - Cost: free tier covers 1 TB/month + 10M requests; ~$0 for personal use.
# =============================================================================

resource "aws_cloudfront_distribution" "main" {
  # Custom domain names (empty list when no custom domain). See locals.tf.
  aliases = local.aliases

  # SSL/TLS certificate used for HTTPS.
  # - Custom domain OFF: CloudFront's built-in *.cloudfront.net certificate.
  # - Custom domain ON : your ACM certificate from domain.tf (us-east-1).
  viewer_certificate {
    acm_certificate_arn            = var.use_custom_domain ? aws_acm_certificate.site[0].arn : null
    cloudfront_default_certificate = var.use_custom_domain ? false : true
    ssl_support_method             = var.use_custom_domain ? "sni-only" : null # sni-only is free; dedicated IP costs $600/mo
    minimum_protocol_version       = "TLSv1.2_2021"                            # reject old insecure TLS
  }

  # ORIGIN = where CloudFront fetches the files from: the S3 website endpoint.
  origin {
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.frontend.id}" # internal label, referenced below

    # The S3 *website* endpoint is treated as a normal web server ("custom
    # origin"), and it only speaks HTTP - hence http-only.
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # what "/" returns
  tags                = local.common_tags

  # CACHE BEHAVIOR = rules for how requests are handled and cached.
  default_cache_behavior {
    # Methods CloudFront accepts. Only GET/HEAD are really needed for a static
    # site; the chat POSTs go to API Gateway directly, not through here.
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    # Don't forward query strings or cookies to S3 (static files don't need
    # them) -> better cache hit rate.
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # Anyone visiting http:// is redirected to https://
    viewer_protocol_policy = "redirect-to-https"

    # How long (seconds) files stay cached at the edge.
    min_ttl     = 0
    default_ttl = 3600  # 1 hour
    max_ttl     = 86400 # 1 day
  }

  # No country blocking - the site is reachable from everywhere.
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
