# Build the three images and push them to ECR by hand (Windows PowerShell).
# Use this for the very first deployment, or whenever GitHub Actions is not set up yet.
#
#   .\scripts\push-images.ps1
#   .\scripts\push-images.ps1 -Region eu-north-1 -Project ms-fargate -Tag latest
param(
    [string]$Region = "eu-north-1",
    [string]$Project = "ms-fargate",
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$account = aws sts get-caller-identity --query Account --output text
$registry = "$account.dkr.ecr.$Region.amazonaws.com"

Write-Host "Logging in to $registry"
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }

foreach ($svc in @("auth", "orders", "notifications")) {
    $image = "$registry/$Project/${svc}:$Tag"
    Write-Host "Building and pushing $image"
    # Fargate tasks are defined as linux/amd64, so build for that even on ARM laptops.
    docker build --platform linux/amd64 -t $image "services/$svc"
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $svc" }
    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "Push failed for $svc" }
}

Write-Host "Done. Pushing the '$Tag' tag starts the CodePipeline blue/green deployment for each service."
