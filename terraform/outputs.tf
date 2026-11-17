# =============================================================================
# outputs.tf - Values printed after `terraform apply`
# =============================================================================
# Outputs expose useful results (URLs, names) so scripts and humans can use
# them. Read one with:   terraform output -raw <name>
#
# Who uses them:
#   - scripts/deploy.sh : api_gateway_url (baked into the frontend build),
#                         s3_frontend_bucket (where to upload the site),
#                         cloudfront_url / custom_domain_url (printed at end)
#   - deploy.yml        : cloudfront_url, api_gateway_url, s3_frontend_bucket
#                         (deployment summary + CloudFront invalidation)
#
# Sorted alphabetically (HashiCorp style guide).
# =============================================================================

# Backend base URL. The frontend sends chat requests to <this>/chat.
output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

# The public website URL (https://xxxx.cloudfront.net). Open this in a browser.
output "cloudfront_url" {
  description = "URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

# Your own domain URL, or "" when the custom domain is off.
output "custom_domain_url" {
  description = "Root URL of the production site"
  value       = var.use_custom_domain ? "https://${var.root_domain}" : ""
}

# Lambda name - handy for viewing logs:  aws logs tail /aws/lambda/<name>
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

# Bucket that the built frontend is uploaded to (aws s3 sync).
output "s3_frontend_bucket" {
  description = "Name of the S3 bucket for frontend"
  value       = aws_s3_bucket.frontend.id
}

# Bucket where conversation memory is stored.
output "s3_memory_bucket" {
  description = "Name of the S3 bucket for memory storage"
  value       = aws_s3_bucket.memory.id
}
