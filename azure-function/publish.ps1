# Publish Azure Function App
# Sets FUNCTIONS_WORKER_RUNTIME environment variable to avoid "local project is None" error

param(
    [string]$FunctionAppName = "func-ghmetrics-prod",
    [switch]$Force
)

# Set the runtime for this session
$env:FUNCTIONS_WORKER_RUNTIME = "powershell"

Write-Host "Publishing to Azure Function App: $FunctionAppName" -ForegroundColor Cyan
Write-Host "FUNCTIONS_WORKER_RUNTIME set to: $env:FUNCTIONS_WORKER_RUNTIME" -ForegroundColor Yellow

# Build the publish command
$publishArgs = @(
    "azure", "functionapp", "publish",
    $FunctionAppName,
    "--nozip"
)

if ($Force) {
    $publishArgs += "--force"
    Write-Host "Force flag enabled (will override Azure app settings)" -ForegroundColor Yellow
}

# Execute publish
func @publishArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "Publish completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Publish failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
