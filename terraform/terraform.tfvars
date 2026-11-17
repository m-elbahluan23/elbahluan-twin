# =============================================================================
# terraform.tfvars - Default VALUES for the variables in variables.tf
# =============================================================================
# Terraform loads this file automatically on every plan/apply/destroy.
# It is committed to git, so NEVER put secrets here.
#
# Note: the deploy scripts always pass -var="project_name=..." and
# -var="environment=...", which override the two values below.
# For prod, values in prod.tfvars (if present) override these too.
# =============================================================================

project_name             = "twin"        # prefix of every resource name
environment              = "dev"         # dev | test | prod (scripts override)
openai_model             = "gpt-4o-mini" # model used by the Lambda
lambda_timeout           = 60            # seconds per Lambda call
api_throttle_burst_limit = 10            # max simultaneous API requests
api_throttle_rate_limit  = 5             # steady API requests per second
use_custom_domain        = false         # true = create domain.tf resources
root_domain              = ""            # e.g. "example.com" when above is true

# openai_api_key is intentionally NOT set here (this file is committed to git).
# Set it in your shell instead:  $env:TF_VAR_openai_api_key = "sk-..."
