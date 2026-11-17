param(
    [string]$Environment = "dev",   # dev | test | prod
    [string]$ProjectName = "twin"
)
$ErrorActionPreference = "Stop"

# Native commands (terraform, npm, aws, uv) don't trigger $ErrorActionPreference
# in Windows PowerShell, so check their exit codes explicitly.
function Assert-LastExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit code $LASTEXITCODE)" }
}

Write-Host "Deploying $ProjectName to $Environment ..." -ForegroundColor Green

$Root = Split-Path $PSScriptRoot -Parent   # project root
Set-Location $Root

# 0. OpenAI API key for Terraform (taken from the shell, or from backend/.env)
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

# 1. Build Lambda package
Write-Host "Building Lambda package..." -ForegroundColor Yellow
Set-Location backend
uv run deploy.py
Assert-LastExit "Lambda package build"
Set-Location ..

# 2. Terraform workspace & apply
Set-Location terraform
terraform init -input=false
Assert-LastExit "terraform init"

$workspaces = terraform workspace list | ForEach-Object { $_.Trim().TrimStart('*').Trim() }
if ($workspaces -notcontains $Environment) {
    terraform workspace new $Environment
} else {
    terraform workspace select $Environment
}
Assert-LastExit "terraform workspace"

if ($Environment -eq "prod") {
    terraform apply -var-file="prod.tfvars" -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
} else {
    terraform apply -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
}
Assert-LastExit "terraform apply"

$ApiUrl         = terraform output -raw api_gateway_url
$FrontendBucket = terraform output -raw s3_frontend_bucket
$CustomUrl      = terraform output -raw custom_domain_url 2>$null
if ($LASTEXITCODE -ne 0) { $CustomUrl = "" }

# 3. Build + deploy frontend
Set-Location ..\frontend

# Create production environment file with API URL.
# Written without a BOM: Windows PowerShell's "-Encoding utf8" adds one, which
# corrupts the variable name so Next.js silently ignores it.
Write-Host "Setting API URL for production..." -ForegroundColor Yellow
[System.IO.File]::WriteAllText((Join-Path (Get-Location) ".env.production"), "NEXT_PUBLIC_API_URL=$ApiUrl`n")

npm install
Assert-LastExit "npm install"
npm run build
Assert-LastExit "npm run build"
aws s3 sync .\out "s3://$FrontendBucket/" --delete
Assert-LastExit "aws s3 sync"
Set-Location ..

# 4. Final summary
$CfUrl = terraform -chdir=terraform output -raw cloudfront_url
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "CloudFront URL : $CfUrl" -ForegroundColor Cyan
if ($CustomUrl) {
    Write-Host "Custom domain  : $CustomUrl" -ForegroundColor Cyan
}
Write-Host "API Gateway    : $ApiUrl" -ForegroundColor Cyan
