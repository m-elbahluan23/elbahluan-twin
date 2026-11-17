# =============================================================================
# variables.tf - INPUTS you can change without editing the code
# =============================================================================
# How a variable gets its value (later wins):
#   1. `default` below
#   2. terraform.tfvars            (committed defaults, no secrets)
#   3. prod.tfvars                 (only for prod, via -var-file)
#   4. TF_VAR_<name> env variable  (used for the OpenAI key)
#   5. -var="name=value"           (scripts pass project_name + environment)
#
# Variables without a default (environment, openai_api_key, project_name)
# MUST be provided, or Terraform stops and asks for them.
#
# Sorted alphabetically (HashiCorp style guide).
# =============================================================================

# Max requests allowed at the SAME instant before API Gateway returns 429.
# Used in api_gateway.tf. Protects your OpenAI bill from bursts/abuse.
variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 10
}

# Steady requests per second allowed (sustained). Used in api_gateway.tf.
variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit"
  type        = number
  default     = 5
}

# Which environment this deploy is for. Goes into every resource name
# (twin-dev-..., twin-prod-...) so environments never collide.
# Passed by the scripts: -var="environment=dev"
variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

# How long one Lambda call may run before AWS stops it. 60s gives OpenAI
# enough time to answer. (API Gateway itself gives up after 30s.)
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

# How many days CloudWatch keeps the Lambda logs before deleting them.
# Used in lambda.tf. Allowed values: 1, 3, 5, 7, 14, 30, 60, 90, ...
variable "log_retention_days" {
  description = "Days to keep Lambda logs in CloudWatch"
  type        = number
  default     = 14
}

# SECRET. Never put it in a .tf / .tfvars file that is committed.
#   Locally : $env:TF_VAR_openai_api_key = "sk-..."  (or backend/.env)
#   CI      : GitHub secret OPENAI_API_KEY -> TF_VAR_openai_api_key
# `sensitive = true` hides it in plan/apply output (it is still stored in
# the state file, which is why the state bucket is private + encrypted).
variable "openai_api_key" {
  description = "OpenAI API key (set via TF_VAR_openai_api_key, never commit it)"
  type        = string
  sensitive   = true
}

# Which OpenAI model the twin uses. Passed to the Lambda as OPENAI_MODEL.
variable "openai_model" {
  description = "OpenAI model name"
  type        = string
  default     = "gpt-4o-mini"
}

# First part of every resource name ("twin" -> twin-dev-api ...).
# Lowercase/digits/hyphens only, because S3 bucket names require that.
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Your domain (e.g. "example.com"), only used when use_custom_domain = true.
variable "root_domain" {
  description = "Apex domain name, e.g. mydomain.com"
  type        = string
  default     = ""
}

# Master switch for everything in domain.tf. false = use *.cloudfront.net
# only, no Route53/ACM resources, no domain cost.
variable "use_custom_domain" {
  description = "Attach a custom domain to CloudFront"
  type        = bool
  default     = false
}
