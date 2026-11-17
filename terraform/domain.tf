# =============================================================================
# domain.tf - OPTIONAL custom domain (e.g. https://example.com)
# =============================================================================
# Status in this project: DISABLED (use_custom_domain = false).
#   Every block below has `count = ... ? 1 : 0` (or an empty for_each), so
#   with the custom domain OFF, NOTHING here is created and it costs $0.
#
# What it would do when use_custom_domain = true:
#   1. Look up your existing Route53 hosted zone for root_domain.
#   2. Request a free SSL certificate (ACM) for example.com + www.example.com.
#   3. Prove you own the domain by adding DNS validation records.
#   4. Wait until AWS marks the certificate as "Issued".
#   5. Point example.com and www.example.com (IPv4 + IPv6) at CloudFront.
#
# Requirements before turning it on:
#   - You own the domain AND it has a PUBLIC hosted zone in Route53
#     (Terraform only READS the zone; it does not create it).
#   - Set use_custom_domain = true and root_domain = "example.com"
#     (e.g. in prod.tfvars).
#
# Permissions needed (deploy role):
#   - route53:*  (AmazonRoute53FullAccess)       for zone lookup + records
#   - acm:*      (AWSCertificateManagerFullAccess) for the certificate
#
# Cost when ON: hosted zone $0.50/month + domain registration (yearly).
#   The ACM certificate is free. Destroy does NOT delete the hosted zone.
# =============================================================================

# STEP 1: Find the existing hosted zone (read-only lookup, creates nothing).
data "aws_route53_zone" "root" {
  count        = var.use_custom_domain ? 1 : 0
  name         = var.root_domain
  private_zone = false
}

# STEP 2: Request the SSL certificate.
# Must be in us-east-1 (provider alias), because CloudFront only accepts
# certificates from that region - even if everything else is in eu-north-1.
resource "aws_acm_certificate" "site" {
  count                     = var.use_custom_domain ? 1 : 0
  provider                  = aws.us_east_1
  domain_name               = var.root_domain
  subject_alternative_names = ["www.${var.root_domain}"] # also covers www.
  validation_method         = "DNS"                      # prove ownership via DNS records
  # When replacing the cert, create the new one before deleting the old,
  # so CloudFront never points at a missing certificate.
  lifecycle { create_before_destroy = true }
  tags = local.common_tags
}

# STEP 3: Create the DNS records that ACM asks for to prove domain ownership.
# One record per domain name (root + www); for_each loops over them.
resource "aws_route53_record" "site_validation" {
  for_each = var.use_custom_domain ? {
    for dvo in aws_acm_certificate.site[0].domain_validation_options :
    dvo.domain_name => dvo
  } : {}

  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 300
  records = [each.value.resource_record_value]
}

# STEP 4: Wait until ACM sees those records and issues the certificate.
# Creates nothing in AWS - it just pauses the apply (usually a few minutes).
resource "aws_acm_certificate_validation" "site" {
  count           = var.use_custom_domain ? 1 : 0
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [
    for r in aws_route53_record.site_validation : r.fqdn
  ]
}

# -----------------------------------------------------------------------------
# STEP 5: Point the domain at CloudFront.
# "Alias" records are Route53's free special records that point directly to
# an AWS resource. A = IPv4, AAAA = IPv6. One pair for root, one for www.
# -----------------------------------------------------------------------------

# example.com -> CloudFront (IPv4)
resource "aws_route53_record" "alias_root" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = var.root_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# example.com -> CloudFront (IPv6)
resource "aws_route53_record" "alias_root_ipv6" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = var.root_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# www.example.com -> CloudFront (IPv4)
resource "aws_route53_record" "alias_www" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "www.${var.root_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# www.example.com -> CloudFront (IPv6)
resource "aws_route53_record" "alias_www_ipv6" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "www.${var.root_domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
