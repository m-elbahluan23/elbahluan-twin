# =============================================================================
# api_gateway.tf - The public HTTPS API in front of the Lambda
# =============================================================================
# What it does:
#   Gives the backend a public URL like
#     https://<id>.execute-api.eu-north-1.amazonaws.com
#   The frontend sends chat messages there; API Gateway forwards each request
#   to the Lambda and returns its response.
#
# Request flow:
#   Browser -> API Gateway (route match) -> integration -> Lambda -> response
#
# Permissions needed (deploy role):
#   - apigateway:*        (AmazonAPIGatewayAdministrator)
#   - lambda:AddPermission (AWSLambda_FullAccess) for aws_lambda_permission
#
# Cost: HTTP APIs are ~$1 per million requests; free tier covers personal use.
# =============================================================================

# The API itself. "HTTP" type = the newer, cheaper, simpler API Gateway (v2).
resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api-gateway"
  protocol_type = "HTTP"
  tags          = local.common_tags

  # CORS = browser rule about which websites may call this API.
  # API Gateway answers the browser's OPTIONS "preflight" request itself.
  # NOTE: allow_origins = "*" lets any site call it; the Lambda also checks
  # CORS_ORIGINS (see lambda.tf).
  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_origins     = ["*"]
    max_age           = 300 # browser caches the preflight answer for 5 min
  }
}

# A "stage" is a deployed version of the API. "$default" means no prefix in
# the URL (no /prod or /dev path). auto_deploy pushes changes immediately.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
  tags        = local.common_tags

  # Rate limiting - protects your OpenAI bill from spam/abuse.
  # burst = max requests at the same moment, rate = steady requests/second.
  # Extra requests get HTTP 429 "Too Many Requests".
  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }
}

# Integration = "where to send requests". AWS_PROXY passes the whole HTTP
# request to the Lambda as-is and returns the Lambda's response as-is.
resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api.invoke_arn
}

# -----------------------------------------------------------------------------
# Routes = which METHOD + PATH are accepted. Anything else returns 404
# without ever reaching (or costing) the Lambda.
# -----------------------------------------------------------------------------

# GET /        -> simple "API is running" response
resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# POST /chat   -> the main endpoint: send a message, get the twin's reply
resource "aws_apigatewayv2_route" "post_chat" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /chat"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# GET /health  -> health check (used to verify a deploy worked)
resource "aws_apigatewayv2_route" "get_health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Gives API Gateway PERMISSION to invoke the Lambda.
# Without this, every request fails with HTTP 500 even though the route
# exists - Lambda rejects callers that aren't explicitly allowed.
# source_arn limits it to THIS API only (any stage /*, any route /*).
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
