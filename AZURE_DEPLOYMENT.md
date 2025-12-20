# Azure Cloud Deployment Guide

This guide explains how to deploy the GitHub Metrics Tracker to Azure using Bicep and Azure Functions.

## Prerequisites

- Azure subscription
- Azure CLI installed
- PowerShell 7.4+
- GitHub Personal Access Token with `repo` scope
- Resource Group in Azure

## Architecture

The deployment creates:
- **Storage Account** with Blob Container for CSV storage
- **Azure Function App** (Consumption plan) with PowerShell 7.4 runtime
- **Timer Trigger** that runs daily at 11:50 PM CET (CRON: `0 50 23 * * *`)
- **Managed Identity** for secure authentication to Storage Account
- **Application Insights** for monitoring and logging
- **Log Analytics Workspace** for centralized logging

## Deployment Steps

### 1. Prepare Your Environment

```powershell
# Set variables
$resourceGroupName = "rg-ghmetrics"
$location = "westeurope"
$subscriptionId = "your-subscription-id"

# Login to Azure
az login

# Set the subscription
az account set --subscription $subscriptionId

# Create resource group
az group create --name $resourceGroupName --location $location
```

### 2. Deploy Bicep Template

```powershell
# Navigate to the infra directory
cd infra

# Validate the template
az deployment group validate `
  --resource-group $resourceGroupName `
  --template-file main.bicep `
  --parameters main.bicepparam

# Deploy the infrastructure
az deployment group create `
  --resource-group $resourceGroupName `
  --template-file main.bicep `
  --parameters main.bicepparam
```

The deployment will output the Function App name and Storage Account name. Save these for the next steps.

### 3. Configure Function App Settings

After deployment, you need to add the sensitive GitHub credentials to the Function App:

```powershell
# Set variables (from deployment output)
$functionAppName = "your-function-app-name"
$githubToken = "your-github-personal-access-token"
$githubUsername = "your-github-username"

# Add settings to Function App
az functionapp config appsettings set `
  --name $functionAppName `
  --resource-group $resourceGroupName `
  --settings `
    GITHUB_TOKEN=$githubToken `
    GITHUB_USERNAME=$githubUsername
```

**Important**: The `@secure` placeholder in the Bicep file indicates these should be added manually or through secure deployment pipelines.

### 4. Deploy Function Code

```powershell
# Navigate to the azure-function directory
cd ../azure-function

# Install Azure Functions Core Tools (if not already installed)
# See: https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local

# Publish the function to Azure
func azure functionapp publish $functionAppName --powershell
```

### 5. Verify Deployment

1. **Check Function App in Azure Portal**:
   - Navigate to your Function App
   - Click on "Functions" → "TimerTrigger"
   - Check the Monitor tab for recent executions

2. **View Logs**:
   ```powershell
   # Stream logs from the function app
   az functionapp log tail `
     --name $functionAppName `
     --resource-group $resourceGroupName
   ```

3. **Check Storage Account**:
   - Go to your Storage Account in Azure Portal
   - Navigate to "Containers" → "metrics"
   - Verify the `github-traffic-metrics.csv` file is present

## Local Development

### Run Function Locally

1. **Update local settings**:
   ```powershell
   cd azure-function
   
   # Edit .env.local with your values
   # GITHUB_TOKEN=your-token
   # GITHUB_USERNAME=your-username
   # STORAGE_ACCOUNT_NAME=your-storage-account
   ```

2. **Start the function locally**:
   ```powershell
   # Using Azure Functions Core Tools
   func start
   
   # The function won't auto-trigger locally
   # To manually test, you can call the function endpoint:
   # POST http://localhost:7071/admin/functions/TimerTrigger
   ```

## Environment Variables

The following environment variables are used (configured as Function App settings in Azure):

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_TOKEN` | GitHub Personal Access Token | `ghp_xxxxx` |
| `GITHUB_USERNAME` | GitHub username | `claestom` |
| `STORAGE_ACCOUNT_NAME` | Azure Storage Account name | `stghmetrics123` |
| `STORAGE_CONTAINER_NAME` | Blob container name | `metrics` |
| `CSV_FILE_NAME` | Output CSV filename | `github-traffic-metrics.csv` |

## Timer Schedule (CRON Expression)

The function runs on this schedule: `0 50 23 * * *`

- **0** - 0 seconds
- **50** - 50 minutes
- **23** - 23:00 (11 PM UTC)
- **\* \* \*** - Every day, every month, every day of week

**Note**: The time is in UTC. For 11:50 PM CET, Azure converts this to 10:50 PM UTC during winter (CET is UTC+1) or 9:50 PM UTC during summer (CEST is UTC+2). Adjust the CRON expression in `TimerTrigger/function.json` if you need a different time.

### Adjust Timer for Your Timezone

Edit `azure-function/TimerTrigger/function.json`:

```json
{
  "bindings": [
    {
      "name": "myTimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 50 22 * * *"
    }
  ]
}
```

Common times:
- 11:50 PM UTC: `0 50 23 * * *`
- 11:50 PM CET (UTC+1): `0 50 22 * * *`
- 11:50 PM CEST (UTC+2): `0 50 21 * * *`

## Troubleshooting

### Function Not Triggering
- Check Application Insights logs in Azure Portal
- Verify Function App settings contain all required environment variables
- Check the timer trigger schedule in `function.json`

### Storage Account Access Issues
- Verify the Managed Identity has "Storage Blob Data Contributor" role
- Check Function App identity configuration
- Ensure storage account allows access from Function App

### GitHub API Errors
- Verify GitHub token has `repo` scope
- Check GitHub API rate limits (5000 requests per hour)
- Ensure the GitHub username matches the token owner

## File Structure

```
ghmetrics/
├── infra/
│   ├── main.bicep              # Main Bicep template
│   └── main.bicepparam         # Parameters file
├── azure-function/
│   ├── TimerTrigger/
│   │   ├── run.ps1             # Function code
│   │   └── function.json        # Timer trigger configuration
│   ├── host.json               # Function host configuration
│   ├── local.settings.json      # Local development settings
│   ├── .env.local              # Local environment variables
│   └── package.json            # Package metadata
├── src/
│   └── github-traffic-metrics.ps1  # Original local script
├── config/
│   └── repo-filter-sample.json     # Repository configuration (example)
├── docs/
└── README.md
```

## Security Considerations

1. **Managed Identity**: The function uses a user-assigned managed identity instead of connection strings
2. **HTTPS Only**: Storage account and Function App enforce HTTPS
3. **Secure Settings**: Use Azure Key Vault for managing sensitive values in production
4. **Least Privilege**: Managed identity has only "Storage Blob Data Contributor" role

## Clean Up Resources

To delete all deployed resources:

```powershell
az group delete --name $resourceGroupName --yes
```

## Additional Resources

- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Timer Trigger for Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer)
- [Azure Storage Blob Bindings](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob)
