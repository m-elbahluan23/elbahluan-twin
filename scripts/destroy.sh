#!/bin/bash
# Bash equivalent of destroy.ps1 (used by GitHub Actions on Linux).
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "❌ Error: Environment parameter is required"
  echo "Usage: $0 <environment> [project_name]"
  exit 1
fi

ENVIRONMENT=$1
PROJECT_NAME=${2:-twin}

if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
  echo "❌ Error: Invalid environment '$ENVIRONMENT'. Use dev, test or prod."
  exit 1
fi

echo "⚠️  Preparing to destroy ${PROJECT_NAME}-${ENVIRONMENT} infrastructure..."

cd "$(dirname "$0")/.."
ROOT=$(pwd)

# Terraform needs every variable without a default, even for destroy.
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

cd "$ROOT/terraform"

AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

echo "🔧 Initializing Terraform with S3 backend..."
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if ! terraform workspace list | sed 's/^[* ]*//' | grep -qx "$ENVIRONMENT"; then
  echo "❌ Error: Workspace '$ENVIRONMENT' does not exist"
  terraform workspace list
  exit 1
fi
terraform workspace select "$ENVIRONMENT"

echo "📦 Emptying S3 buckets..."
for BUCKET in "${PROJECT_NAME}-${ENVIRONMENT}-frontend-${AWS_ACCOUNT_ID}" \
              "${PROJECT_NAME}-${ENVIRONMENT}-memory-${AWS_ACCOUNT_ID}"; do
  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    echo "  Emptying $BUCKET..."
    aws s3 rm "s3://$BUCKET" --recursive
  else
    echo "  $BUCKET not found, skipping"
  fi
done

echo "🔥 Running terraform destroy..."
if [ "$ENVIRONMENT" = "prod" ] && [ -f prod.tfvars ]; then
  terraform destroy -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
else
  terraform destroy -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
fi

echo "✅ Infrastructure for $ENVIRONMENT has been destroyed!"
