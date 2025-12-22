# GitHub Metrics Tracker

Track GitHub repository traffic (views and clones) over time. Collects daily metrics and stores them in CSV format.

## What It Does

- Fetches **views** and **clones** data for all your public repositories
- Stores historical data (GitHub only keeps 14 days)
- Tracks data from 13 days ago (ensuring complete data before GitHub purges it)
- Outputs: CSV with date columns showing `views(clones)` per repository

## Usage Options

### Get the code

```powershell
# Clone and enter the repo
git clone https://github.com/claestom/GitHub-metrics-tracker.git
cd GitHub-metrics-tracker
```

### Option 1: Local Script

Run manually or via scheduled task on your local machine.

**Setup:**
```powershell
# 1. Create .env file in root directory
GITHUB_TOKEN=ghp_your_token_here
GITHUB_USERNAME=your_username

# 2. Run the script
cd src
.\github-traffic-metrics.ps1
```

**Output:** `outputs/github-traffic-metrics.csv`

**Schedule (optional):**
- Windows: Task Scheduler
- Linux/Mac: cron job

---

### Option 2: Azure Functions (Automated)

Deploy to Azure for fully automated daily collection at 11:50 PM CET.

**Prerequisites:**
- Azure subscription
- Azure CLI installed
- PowerShell 7.4+

**Deploy:**
```powershell
# 1. Login and set variables
az login
$rg = "<rg-name>"
$location = "westeurope"

# 2. Create resource group
az group create --name $rg --location $location

# 3. Deploy infrastructure (storage, function app, identity)
az deployment group create `
  --resource-group $rg `
  --template-file infra/main.bicep `
  --parameters infra/main.bicepparam

# 4. Get function app name from outputs
$funcApp = az functionapp list -g $rg --query "[0].name" -o tsv

# 5. Set GitHub credentials in the Azure Functions config
az functionapp config appsettings set -g $rg -n $funcApp `
  --settings GITHUB_TOKEN="ghp_new_token" GITHUB_USERNAME="your_username"

# 6. Publish function code
cd azure-function
func azure functionapp publish $funcApp --nozip
```

**What Gets Created:**
- Storage Account (stores CSV in `metrics` container)
- Function App (PowerShell 7.4, Consumption plan)
- User-Assigned Managed Identity (secure storage access)
- Application Insights (monitoring)

---

## Power BI Usage (SAS + .pbit)

Use the template in `powerbi/` to visualize the CSV with your own storage.

- Desktop setup:
  - Open the `.pbit` → enter the SAS URL when prompted.
  - Data source credentials: choose `Anonymous` (SAS is in the URL).
  - Refresh to apply all existing transform steps.
- Publish to Service:
  - Dataset → Settings → Data source credentials → set to `Anonymous` for the blob domain.
  - Enable Scheduled refresh (ensure SAS expiry is sufficient).
- SAS scope: prefer blob-level SAS with `r` permission only; rotate with brief overlap.