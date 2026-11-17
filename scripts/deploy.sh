#!/bin/bash
# Bash equivalent of deploy.ps1 (used by GitHub Actions on Linux).
set -euo pipefail

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# Project root
cd "$(dirname "$0")/.."
ROOT=$(pwd)

# 0. OpenAI API key for Terraform (from env, or from backend/.env locally)
if [ -z "${TF_VAR_openai_api_key:-}" ] && [ -f backend/.env ]; then
  LINE=$(grep -E '^\s*OPENAI_API_KEY\s*=' backend/.env | tail -n 1 || true)
  if [ -n "$LINE" ]; then
    VALUE=${LINE#*=}
    VALUE=$(echo "$VALUE" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s/^['\"]//" -e "s/['\"]\$//")
    export TF_VAR_openai_api_key="$VALUE"
  fi
fi
if [ -z "${TF_VAR_openai_api_key:-}" ]; then
  echo "❌ OpenAI API key not found. Set TF_VAR_openai_api_key (OPENAI_API_KEY secret in CI) or OPENAI_API_KEY in backend/.env"
  exit 1
fi

# 1. Build Lambda package
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Terraform workspace & apply
cd "$ROOT/terraform"
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if ! terraform workspace list | sed 's/^[* ]*//' | grep -qx "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

if [ "$ENVIRONMENT" = "prod" ] && [ -f prod.tfvars ]; then
  terraform apply -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
else
  terraform apply -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
fi

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

# 3. Build + deploy frontend
cd "$ROOT/frontend"
echo "📝 Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

npm install
npm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
cd "$ROOT"

# 4. Final summary
CF_URL=$(terraform -chdir=terraform output -raw cloudfront_url)
echo "✅ Deployment complete!"
echo "🌐 CloudFront URL : $CF_URL"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Custom domain  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"
