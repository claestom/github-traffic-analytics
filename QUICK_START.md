# Quick Start: Deploy to Azure

## One-Command Deployment (after prerequisites)

```powershell
# 1. Set variables
$rg = "rg-ghmetrics"
$location = "westeurope"
$githubToken = "ghp_xxxxx"
$githubUsername = "claestom"

# 2. Create resource group
az group create --name $rg --location $location

# 3. Deploy infrastructure
az deployment group create `
  --resource-group $rg `
  --template-file infra/main.bicep `
  --parameters infra/main.bicepparam

# 4. Get function app name from output
$funcApp = "func-ghmetrics-prod-xxxxx"

# 5. Configure secrets
az functionapp config appsettings set `
  --name $funcApp `
  --resource-group $rg `
  --settings GITHUB_TOKEN=$githubToken GITHUB_USERNAME=$githubUsername

# 6. Deploy function code
cd azure-function
func azure functionapp publish $funcApp --powershell
```

## What Gets Created

| Resource | Name | Purpose |
|----------|------|---------|
| Storage Account | `stghmetrics{hash}` | Stores CSV file |
| Function App | `func-ghmetrics-prod` | Runs the scheduled task |
| App Service Plan | `plan-ghmetrics-prod` | Consumption plan (pay-per-use) |
| Application Insights | `ai-ghmetrics-prod` | Monitoring & logging |
| Managed Identity | `id-ghmetrics-prod` | Secure authentication |

## Schedule

**Time**: 11:50 PM CET (22:50 UTC in winter, 21:50 UTC in summer)
**Frequency**: Daily
**CRON**: `0 50 23 * * *`

## View Logs

```powershell
# Stream logs
az functionapp log tail --name $funcApp --resource-group $rg

# Or in Azure Portal: Function App → Monitor → Logs
```

## Check Results

1. **Azure Portal**:
   - Function App → Functions → TimerTrigger → Monitor
   - Storage Account → Containers → metrics → github-traffic-metrics.csv

2. **Download CSV**:
```powershell
az storage blob download `
  --account-name stghmetrics{hash} `
  --container-name metrics `
  --name github-traffic-metrics.csv `
  --file ./metrics.csv
```

## Troubleshoot

```powershell
# Check function app settings
az functionapp config appsettings list --name $funcApp --resource-group $rg

# View recent executions
az monitor metrics list --resource "/subscriptions/{id}/resourceGroups/$rg/providers/Microsoft.Web/sites/$funcApp" --metric "FunctionExecutionCount"

# Delete everything (clean up)
az group delete --name $rg --yes
```

## Local Testing

```powershell
# Prepare local environment
cd azure-function
# Edit .env.local with your GitHub credentials

# Start local function runtime
func start

# Manually trigger (in another terminal)
curl -X POST http://localhost:7071/admin/functions/TimerTrigger
```

## Key Files

- **Infrastructure**: `infra/main.bicep` - All Azure resources
- **Function Code**: `azure-function/TimerTrigger/run.ps1` - Main logic
- **Timer Schedule**: `azure-function/TimerTrigger/function.json` - Change time here
- **Documentation**: `AZURE_DEPLOYMENT.md` - Full guide

## Security Notes

✅ **Done automatically**:
- Managed Identity (no passwords)
- HTTPS only
- Encrypted storage
- Role-based access control

⚠️ **Consider for production**:
- Use Azure Key Vault for GitHub token
- Enable VNet integration
- Set up budget alerts
- Configure diagnostic logging

## Costs

Typical monthly: **$2-3** (very cheap!)
- 1 execution per day × 30 = 30 executions
- At $0.50 per 1M executions = minimal cost

## Need Help?

See `AZURE_DEPLOYMENT.md` for detailed troubleshooting and architecture information.
