# =============================================================================
# lambda.tf - The backend: Lambda function, its IAM role, and its log group
# =============================================================================
# What runs here:
#   The Python FastAPI backend (backend/), packaged as
#   backend/lambda-deployment.zip by `backend/deploy.py`. It receives chat
#   messages from API Gateway, calls OpenAI, and saves the conversation to
#   the memory S3 bucket.
#
# Two kinds of permissions are involved - don't mix them up:
#   A) DEPLOY permissions: what the GitHub Actions role
#      `github-actions-twin-deploy` needs to CREATE these resources:
#        - iam:CreateRole, AttachRolePolicy, PassRole ... (inline policy
#          "github-actions-additional")
#        - lambda:*                       (AWSLambda_FullAccess)
#        - logs:CreateLogGroup, PutRetentionPolicy, DeleteLogGroup ...
#          on /aws/lambda/twin-*          (statement "ManageTwinLambdaLogGroups"
#                                          in the inline policy)
#   B) RUNTIME permissions: what the Lambda ITSELF may do while running.
#      Given by `aws_iam_role.lambda_role` below (write logs, use S3).
#      Calling OpenAI needs no AWS permission - it is a normal HTTPS call.
#
# Cost: Lambda is pay-per-request; for personal traffic it stays in the
# free tier (~$0). OpenAI usage is billed separately by OpenAI.
# =============================================================================

# -----------------------------------------------------------------------------
# IAM role = the "identity" the Lambda runs as (RUNTIME permissions)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"
  tags = local.common_tags

  # Trust policy: WHO may use (assume) this role.
  # Only the Lambda service - no user or other service can use it.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# AWS-managed policy: lets the Lambda write its logs to CloudWatch
# (logs:CreateLogStream, logs:PutLogEvents). Without it you'd see no logs.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# No Bedrock policy needed - the Lambda calls OpenAI over the internet.

# AWS-managed policy: lets the Lambda read/write S3 (the memory bucket).
# NOTE: this is broad (ALL buckets in the account). A tighter option would be
# an inline policy limited to aws_s3_bucket.memory.arn.
resource "aws_iam_role_policy_attachment" "lambda_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

# -----------------------------------------------------------------------------
# The Lambda function itself
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "api" {
  # The code package. Built by backend/deploy.py before terraform apply.
  # (destroy.* creates an empty placeholder zip if it's missing, because
  # Terraform reads this file even when destroying.)
  filename      = "${path.module}/../backend/lambda-deployment.zip"
  function_name = "${local.name_prefix}-api" # e.g. twin-dev-api
  role          = aws_iam_role.lambda_role.arn

  # Entry point: function `handler` in file lambda_handler.py
  handler = "lambda_handler.handler"

  # Hash of the zip. When the code changes, the hash changes, and Terraform
  # uploads the new code. Same hash = no re-upload.
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda-deployment.zip")

  runtime       = "python3.12"
  architectures = ["x86_64"]
  timeout       = var.lambda_timeout # seconds; OpenAI calls can be slow
  tags          = local.common_tags

  # Environment variables the Python code reads with os.environ.
  environment {
    variables = {
      # Which website origins may call the API (browser CORS check).
      CORS_ORIGINS = var.use_custom_domain ? "https://${var.root_domain},https://www.${var.root_domain}" : "https://${aws_cloudfront_distribution.main.domain_name}"
      # Where to store conversation memory.
      S3_BUCKET = aws_s3_bucket.memory.id
      USE_S3    = "true"
      # OpenAI credentials/model. The key comes from TF_VAR_openai_api_key
      # (GitHub secret OPENAI_API_KEY in CI). trimspace removes stray newlines.
      # NOTE: visible in the Lambda console and stored in Terraform state.
      OPENAI_API_KEY = trimspace(var.openai_api_key)
      OPENAI_MODEL   = var.openai_model
    }
  }

  # Wait for the distribution, and for the log group so Lambda doesn't
  # auto-create an unmanaged one on first invoke.
  depends_on = [
    aws_cloudfront_distribution.main,
    aws_cloudwatch_log_group.lambda,
  ]
}

# -----------------------------------------------------------------------------
# CloudWatch log group for the Lambda's logs (print / errors)
# -----------------------------------------------------------------------------
# Log group managed by Terraform so it has a retention period and is
# removed on destroy (Lambda's auto-created groups are kept forever).
# The name MUST be exactly /aws/lambda/<function_name> - that's where
# Lambda writes automatically.
# Deploy permission: logs:CreateLogGroup etc. on /aws/lambda/twin-*
# (if missing -> AccessDeniedException during deploy).
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days # older logs auto-deleted
  tags              = local.common_tags
}
