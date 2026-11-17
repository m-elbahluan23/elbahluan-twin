param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    [string]$ProjectName = "twin"
)

# Native commands (terraform, aws) don't throw on failure in Windows PowerShell,
# so check their exit codes explicitly.
function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit code $LASTEXITCODE)" }
}

# Validate environment parameter
if ($Environment -notmatch '^(dev|test|prod)$') {
    Write-Host "Error: Invalid environment '$Environment'" -ForegroundColor Red
    Write-Host "Available environments: dev, test, prod" -ForegroundColor Yellow
    exit 1
}

Write-Host "Preparing to destroy $ProjectName-$Environment infrastructure..." -ForegroundColor Yellow

$Root = Split-Path $PSScriptRoot -Parent

# Terraform needs every variable without a default, even for destroy.
# Load the OpenAI key the same way deploy.ps1 does.
if (-not $env:TF_VAR_openai_api_key) {
    $envFile = Join-Path $Root "backend\.env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match '^\s*OPENAI_API_KEY\s*=' } | Select-Object -Last 1
        if ($line) {
            $env:TF_VAR_openai_api_key = ($line -split '=', 2)[1].Trim().Trim("'").Trim('"')
        }
    }
}
if (-not $env:TF_VAR_openai_api_key) {
    throw "OpenAI API key not found. Set `$env:TF_VAR_openai_api_key or OPENAI_API_KEY in backend/.env"
}

# lambda.tf hashes the Lambda zip, and Terraform evaluates that even on destroy.
# The zip is a build artifact (not in git), so create a placeholder if missing.
$zipPath = Join-Path $Root "backend\lambda-deployment.zip"
if (-not (Test-Path $zipPath)) {
    Write-Host "Creating placeholder Lambda package for destroy..." -ForegroundColor Gray
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    $zip.Dispose()
}

# Navigate to terraform directory
Set-Location (Join-Path $Root "terraform")

# Get AWS Account ID for backend configuration and bucket names
$awsAccountId = aws sts get-caller-identity --query Account --output text
Assert-LastExit "aws sts get-caller-identity"
$awsRegion = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "us-east-1" }

# Initialize terraform with S3 backend
Write-Host "Initializing Terraform with S3 backend..." -ForegroundColor Yellow
terraform init -input=false `
  -backend-config="bucket=twin-terraform-state-$awsAccountId" `
  -backend-config="key=$Environment/terraform.tfstate" `
  -backend-config="region=$awsRegion" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -backend-config="encrypt=true"
Assert-LastExit "terraform init"

# Check if workspace exists (exact match, not substring)
$workspaces = terraform workspace list | ForEach-Object { $_.Trim().TrimStart('*').Trim() }
if ($workspaces -notcontains $Environment) {
    Write-Host "Error: Workspace '$Environment' does not exist" -ForegroundColor Red
    Write-Host "Available workspaces:" -ForegroundColor Yellow
    terraform workspace list
    exit 1
}

# Select the workspace
terraform workspace select $Environment
Assert-LastExit "terraform workspace select"

Write-Host "Emptying S3 buckets..." -ForegroundColor Yellow

# Define bucket names with account ID
$Buckets = @(
    "$ProjectName-$Environment-frontend-$awsAccountId",
    "$ProjectName-$Environment-memory-$awsAccountId"
)

foreach ($Bucket in $Buckets) {
    aws s3api head-bucket --bucket $Bucket 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Emptying $Bucket..." -ForegroundColor Gray
        aws s3 rm "s3://$Bucket" --recursive
        Assert-LastExit "Emptying $Bucket"
    } else {
        Write-Host "  $Bucket not found, skipping" -ForegroundColor Gray
    }
}

Write-Host "Running terraform destroy..." -ForegroundColor Yellow

# Run terraform destroy with auto-approve
if ($Environment -eq "prod" -and (Test-Path "prod.tfvars")) {
    terraform destroy -var-file="prod.tfvars" -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
} else {
    terraform destroy -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
}
Assert-LastExit "terraform destroy"

Write-Host "Infrastructure for $Environment has been destroyed!" -ForegroundColor Green
Write-Host ""
Write-Host "  To remove the workspace completely, run:" -ForegroundColor Cyan
Write-Host "   terraform workspace select default" -ForegroundColor White
Write-Host "   terraform workspace delete $Environment" -ForegroundColor White
