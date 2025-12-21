# GitHub Metrics Tracker

Track GitHub repository traffic (views and clones) over time. Collects daily metrics and stores them in CSV format.

## What It Does

- Fetches **views** and **clones** data for all your public repositories
- Stores historical data (GitHub only keeps 14 days)
- Tracks data from 13 days ago (ensuring complete data before GitHub purges it)
- Outputs: CSV with date columns showing `views(clones)` per repository

## Usage Options

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
$rg = "rg-ghmetrics-demo01"
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

# 5. Set GitHub credentials (create new PAT with repo scope)
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

**Monitor:**
```powershell
# View logs
az functionapp log tail -g $rg -n $funcApp

# Download CSV
az storage blob download --account-name <storage_name> `
  --container-name metrics --name github-traffic-metrics.csv --file metrics.csv
```

**Clean up:**
```powershell
az group delete --name $rg --yes
```

---

## CSV Format

```
Repository,2025-12-01,2025-12-02,...,Total
repo-name-1,5(2),3(1),...,8(3)
repo-name-2,0(0),12(4),...,12(4)
TOTAL,5(2),15(5),...,20(7)
```
- Format: `views(clones)`
- TOTAL row: sum across all repositories per day

## Repository Structure

```
├── src/                          # Local script
│   └── github-traffic-metrics.ps1
├── azure-function/               # Azure deployment
│   ├── TimerTrigger/
│   │   ├── run.ps1              # Function logic
│   │   └── function.json        # Timer schedule
│   ├── host.json
│   └── requirements.psd1        # PowerShell modules
├── infra/                        # Infrastructure as Code
│   ├── main.bicep               # Azure resources
│   └── main.bicepparam          # Parameters
├── config/                       # Configuration samples
└── outputs/                      # Local script output
```

## License

MIT
