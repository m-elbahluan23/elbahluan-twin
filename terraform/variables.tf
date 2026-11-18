# Inputs. Defaults are set in terraform.tfvars; the deploy scripts pass
# project_name and environment, and CI passes the OpenAI key via TF_VAR_.

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit"
  type        = number
  default     = 10
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit"
  type        = number
  default     = 5
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60
}

variable "log_retention_days" {
  description = "Days to keep Lambda logs in CloudWatch"
  type        = number
  default     = 14
}

# Never commit this. Set TF_VAR_openai_api_key (GitHub secret OPENAI_API_KEY in CI).
variable "openai_api_key" {
  description = "OpenAI API key (set via TF_VAR_openai_api_key, never commit it)"
  type        = string
  sensitive   = true
}

variable "openai_model" {
  description = "OpenAI model name"
  type        = string
  default     = "gpt-4o-mini"
}

# Lowercase only, because it becomes part of S3 bucket names.
variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "root_domain" {
  description = "Apex domain name, e.g. mydomain.com"
  type        = string
  default     = ""
}

variable "use_custom_domain" {
  description = "Attach a custom domain to CloudFront"
  type        = bool
  default     = false
}
