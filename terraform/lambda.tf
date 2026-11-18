# Backend: the FastAPI Lambda, the IAM role it runs as, and its log group.
# The zip is built by backend/deploy.py before terraform apply.

# Role the Lambda runs as. Only the Lambda service can assume it.
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"
  tags = local.common_tags

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

# Lets the Lambda write its logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# No Bedrock policy needed - the Lambda calls OpenAI over the internet.

# TODO: broader than needed (all buckets); could be limited to the memory bucket.
resource "aws_iam_role_policy_attachment" "lambda_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_lambda_function" "api" {
  filename      = "${path.module}/../backend/lambda-deployment.zip"
  function_name = "${local.name_prefix}-api"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_handler.handler"
  # Code is re-uploaded only when the zip's hash changes.
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda-deployment.zip")
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  timeout          = var.lambda_timeout
  tags             = local.common_tags

  environment {
    variables = {
      CORS_ORIGINS = var.use_custom_domain ? "https://${var.root_domain},https://www.${var.root_domain}" : "https://${aws_cloudfront_distribution.main.domain_name}"
      S3_BUCKET    = aws_s3_bucket.memory.id
      USE_S3       = "true"
      # From TF_VAR_openai_api_key. Visible in the Lambda console and in state.
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

# Managed here so logs expire and the group is removed on destroy.
# The deploy role needs logs:* on /aws/lambda/twin-* to create it.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}
