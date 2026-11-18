# Default values (committed - no secrets here).
# The deploy scripts override project_name and environment; prod.tfvars
# overrides these for prod.

project_name             = "twin"
environment              = "dev"
openai_model             = "gpt-4o-mini"
lambda_timeout           = 60
api_throttle_burst_limit = 10
api_throttle_rate_limit  = 5
use_custom_domain        = false
root_domain              = ""

# openai_api_key is intentionally NOT set here (this file is committed to git).
# Set it in your shell instead:  $env:TF_VAR_openai_api_key = "sk-..."
