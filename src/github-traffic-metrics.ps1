# GitHub Repository Traffic Metrics Scraper
# Collects clones and views data for personal public repositories
#
# Output Format: Each cell shows "views(clones)" where:
#   - views = Total page views for that repository on that date
#   - clones = Total repository clones/downloads for that date
#   Example: "45(4)" means 45 views and 4 clones on that date

param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubUsername
)

# Load configuration from .env file
$envPath = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
if (-not (Test-Path $envPath)) {
    $envPath = Join-Path $PSScriptRoot "..\\.env"
}

$envLoaded = $false
if (Test-Path $envPath) {
    $envLoaded = $true
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            $value = $value -replace '^["''](.*)[""'']$', '$1'
            Set-Variable -Name $name -Value $value -Scope Script
        }
    }
}

# Use .env values if parameters not provided
if (-not $GitHubToken -and $envLoaded -and $GITHUB_TOKEN) {
    $GitHubToken = $GITHUB_TOKEN
    Write-Host "Using GitHub token from .env file" -ForegroundColor Green
}

if (-not $GitHubUsername -and $envLoaded -and $GITHUB_USERNAME) {
    $GitHubUsername = $GITHUB_USERNAME
    Write-Host "Using GitHub username from .env file" -ForegroundColor Green
}

# Validate required parameters
if (-not $GitHubToken) {
    Write-Error "GitHub token is required. Either provide -GitHubToken parameter or set GITHUB_TOKEN in .env file"
    exit 1
}

if (-not $GitHubUsername) {
    Write-Error "GitHub username is required. Either provide -GitHubUsername parameter or set GITHUB_USERNAME in .env file"
    exit 1
}

# Create outputs directory if it doesn't exist
$outputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "outputs"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$outputFile = Join-Path $outputDir "github-traffic-metrics.csv"

# GitHub API headers
$headers = @{
    'Authorization' = "token $GitHubToken"
    'Accept' = 'application/vnd.github.v3+json'
    'User-Agent' = 'PowerShell-GitHubTrafficScraper'
}

# Display nice title and description
Write-Host ""
Write-Host "===============================================================" -ForegroundColor Blue
Write-Host "          GitHub Repository Traffic Metrics Scraper           " -ForegroundColor White
Write-Host "===============================================================" -ForegroundColor Blue
Write-Host ""
Write-Host "This script captures historical GitHub traffic data before it expires from the 14-day window." -ForegroundColor Gray
Write-Host "It builds an incremental CSV dataset by collecting the oldest available data each day." -ForegroundColor Gray
Write-Host ""
Write-Host "Output Format: Each cell shows 'views(clones)' where:" -ForegroundColor Yellow
Write-Host "  * views  = Total page views for that repository on that date" -ForegroundColor White
Write-Host "  * clones = Total repository clones/downloads for that date" -ForegroundColor White
Write-Host "  * Example: '45(4)' means 45 views and 4 clones on that date" -ForegroundColor Green
Write-Host ""
Write-Host "Fetching GitHub repositories for user: $GitHubUsername" -ForegroundColor Green

try {
    # Get all public repositories for the user
    $reposUrl = "https://api.github.com/users/$GitHubUsername/repos?type=owner&per_page=100"
    $repositories = Invoke-RestMethod -Uri $reposUrl -Headers $headers -Method Get
    
    $publicRepos = $repositories | Where-Object { $_.private -eq $false -and $_.owner.login -eq $GitHubUsername -and $_.fork -eq $false }
    
    Write-Host "Processing $($publicRepos.Count) repositories" -ForegroundColor Cyan
    
    # Use SAME date for all repositories: exactly 13 days ago
    $targetDate = (Get-Date).AddDays(-13).ToString('yyyy-MM-dd')
    
    # Load existing CSV data if it exists
    $existingData = @{}
    if (Test-Path $outputFile) {
        $existingCsv = Import-Csv $outputFile
        foreach ($row in $existingCsv) {
            $repoName = $row.Repository
            if (-not $existingData.ContainsKey($repoName)) {
                $existingData[$repoName] = @{}
            }
            
            # Import all date columns (skip Repository and Total columns)
            $row.PSObject.Properties | ForEach-Object {
                if ($_.Name -ne "Repository" -and $_.Name -ne "Total") {
                    $existingData[$repoName][$_.Name] = $_.Value
                }
            }
        }
        $isFirstRun = $false
        Write-Host "`nFound existing CSV file, loading data..." -ForegroundColor Green
    } else {
        $isFirstRun = $true
        Write-Host "`nNo existing CSV found. FIRST RUN DETECTED - will backfill 14 days of historical data (t-14 through t-1)" -ForegroundColor Yellow
    }
    
    # Determine which dates to collect based on first run vs. subsequent run
    $datesToCollect = @()
    if ($isFirstRun) {
        # First run: collect 14 days of history (t-14 through t-1)
        for ($i = 15; $i -ge 2; $i--) {
            $datesToCollect += (Get-Date).AddDays(-$i).ToString('yyyy-MM-dd')
        }
        Write-Host "First run mode: collecting 14 days of historical data" -ForegroundColor Cyan
    } else {
        # Subsequent runs: only collect 2 days before (t-2)
        $datesToCollect += (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
        Write-Host "Daily append mode: collecting data for 1 day" -ForegroundColor Cyan
    }
    
    Write-Host "Target date(s): $($datesToCollect -join ', ')" -ForegroundColor Yellow
    
    $newDayData = @{}  # Format: $newDayData[$date][$repoName] = "views(clones)"
    $totalViewsForDay = 0
    $totalClonesForDay = 0
    
    foreach ($targetDate in $datesToCollect) {
        Write-Host "`nCollecting data for date: $targetDate" -ForegroundColor Cyan
        $newDayData[$targetDate] = @{}
        
        foreach ($repo in $publicRepos) {
            Write-Host "  Processing repository: $($repo.name)" -ForegroundColor Yellow
            
            try {
                # Get traffic views (last 14 days)
                $viewsUrl = "https://api.github.com/repos/$GitHubUsername/$($repo.name)/traffic/views"
                $viewsData = Invoke-RestMethod -Uri $viewsUrl -Headers $headers -Method Get
                
                # Get traffic clones (last 14 days)  
                $clonesUrl = "https://api.github.com/repos/$GitHubUsername/$($repo.name)/traffic/clones"
                $clonesData = Invoke-RestMethod -Uri $clonesUrl -Headers $headers -Method Get
                
                $viewCount = 0
                $cloneCount = 0
                
                # Look for views data for the specific target date
                if ($viewsData.views.Count -gt 0) {
                    $targetViewDay = $viewsData.views | Where-Object {
                        try {
                            # Convert timestamp to DateTime if it's a string, otherwise it's already a DateTime object
                            $timestampDate = if ($_.timestamp -is [DateTime]) {
                                $_.timestamp
                            } elseif ($_.timestamp -is [string]) {
                                if ($_.timestamp -match '^\d{4}-\d{2}-\d{2}') {
                                    [DateTime]::Parse($_.timestamp.Substring(0, 10))
                                } else {
                                    [DateTime]::Parse($_.timestamp)
                                }
                            } else {
                                $_.timestamp
                            }
                            
                            # Compare date parts only (ignore time)
                            $dateStr = $timestampDate.ToString('yyyy-MM-dd')
                            $dateStr -eq $targetDate
                        } catch {
                            $false
                        }
                    }
                    if ($targetViewDay) {
                        $viewCount = $targetViewDay.count
                    }
                }
                
                # Look for clones data for the specific target date
                if ($clonesData.clones.Count -gt 0) {
                    $targetCloneDay = $clonesData.clones | Where-Object {
                        try {
                            # Convert timestamp to DateTime if it's a string, otherwise it's already a DateTime object
                            $timestampDate = if ($_.timestamp -is [DateTime]) {
                                $_.timestamp
                            } elseif ($_.timestamp -is [string]) {
                                if ($_.timestamp -match '^\d{4}-\d{2}-\d{2}') {
                                    [DateTime]::Parse($_.timestamp.Substring(0, 10))
                                } else {
                                    [DateTime]::Parse($_.timestamp)
                                }
                            } else {
                                $_.timestamp
                            }
                            
                            # Compare date parts only (ignore time)
                            $dateStr = $timestampDate.ToString('yyyy-MM-dd')
                            $dateStr -eq $targetDate
                        } catch {
                            $false
                        }
                    }
                    if ($targetCloneDay) {
                        $cloneCount = $targetCloneDay.count
                    }
                }
                
                # Format data as "views(clones)"
                $formattedData = "$viewCount($cloneCount)"
                $newDayData[$targetDate][$repo.name] = $formattedData
                
                # Only add to daily totals if this is the most recent date (for logging)
                if ($targetDate -eq $datesToCollect[-1]) {
                    $totalViewsForDay += $viewCount
                    $totalClonesForDay += $cloneCount
                }
                
                Write-Host "    Views = $viewCount & Clones = $cloneCount" -ForegroundColor Gray
                
                # Rate limiting - GitHub allows 5000 requests per hour
                Start-Sleep -Milliseconds 100
                
            } catch {
                Write-Warning "Failed to get traffic data for repository '$($repo.name)' on $targetDate : $($_.Exception.Message)"
                Write-Host "    Views = 0 & Clones = 0" -ForegroundColor Gray
                $newDayData[$targetDate][$repo.name] = "0(0)"
            }
        }
    }
    
    # Build the final data structure
    $allRepositories = @($publicRepos.name) + @("TOTAL")
    $allDates = @()
    
    # Get all unique dates from existing data
    if ($existingData.Count -gt 0) {
        $existingDates = $existingData.Values | ForEach-Object { $_.Keys } | Sort-Object | Get-Unique
        $allDates += $existingDates
    }
    
    # Add newly collected dates (avoiding duplicates in daily append mode)
    foreach ($date in $datesToCollect) {
        if ($date -notin $allDates) {
            $allDates += $date
        }
    }
    
    $allDates = $allDates | Sort-Object
    
    # Create the output data
    $outputData = @()
    foreach ($repoName in $allRepositories) {
        $row = [PSCustomObject]@{
            Repository = $repoName
        }
        
        $totalViews = 0
        $totalClones = 0
        
        foreach ($date in $allDates) {
            if ($repoName -eq "TOTAL") {
                # Calculate totals for each date
                $dayTotalViews = 0
                $dayTotalClones = 0
                foreach ($repo in $publicRepos.name) {
                    $repoData = if ($newDayData.ContainsKey($date) -and $newDayData[$date].ContainsKey($repo)) {
                        # Data from current run
                        $newDayData[$date][$repo]
                    } elseif ($existingData.ContainsKey($repo) -and $existingData[$repo].ContainsKey($date)) {
                        # Data from existing CSV
                        $existingData[$repo][$date]
                    } else {
                        "0(0)"
                    }
                    
                    if ($repoData -match "(\d+)\((\d+)\)") {
                        $dayTotalViews += [int]$matches[1]
                        $dayTotalClones += [int]$matches[2]
                    }
                }
                $totalViews += $dayTotalViews
                $totalClones += $dayTotalClones
                $row | Add-Member -MemberType NoteProperty -Name $date -Value "$dayTotalViews($dayTotalClones)"
            } else {
                # Regular repository data
                $repoData = if ($newDayData.ContainsKey($date) -and $newDayData[$date].ContainsKey($repoName)) {
                    # Data from current run
                    $newDayData[$date][$repoName]
                } elseif ($existingData.ContainsKey($repoName) -and $existingData[$repoName].ContainsKey($date)) {
                    # Data from existing CSV
                    $existingData[$repoName][$date]
                } else {
                    "0(0)"
                }
                
                if ($repoData -match "(\d+)\((\d+)\)") {
                    $totalViews += [int]$matches[1]
                    $totalClones += [int]$matches[2]
                }
                
                $row | Add-Member -MemberType NoteProperty -Name $date -Value $repoData
            }
        }
        
        # Add total column for each repository
        if ($repoName -ne "TOTAL") {
            $row | Add-Member -MemberType NoteProperty -Name "Total" -Value "$totalViews($totalClones)"
        } else {
            $row | Add-Member -MemberType NoteProperty -Name "Total" -Value "$totalViews($totalClones)"
        }
        
        $outputData += $row
    }
    
    # Export to CSV
    $outputData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
    
    Write-Host "`nResults saved to: $outputFile" -ForegroundColor Green
    
    if ($isFirstRun) {
        Write-Host "`nBackfilled $($datesToCollect.Count) days of historical data" -ForegroundColor Cyan
        Write-Host "Date range: $($datesToCollect[0]) to $($datesToCollect[-1])" -ForegroundColor Cyan
    } else {
        Write-Host "`nSummary for $($datesToCollect[-1]):" -ForegroundColor Cyan
        Write-Host "  Total Repositories: $($publicRepos.Count)" -ForegroundColor White
        Write-Host "  Total Views: $totalViewsForDay" -ForegroundColor White  
        Write-Host "  Total Clones: $totalClonesForDay" -ForegroundColor White
    }
    
} catch {
    Write-Error "Failed to fetch repository data: $($_.Exception.Message)"
    Write-Host "Please ensure your GitHub token has the correct permissions (repo scope for private repos, or public_repo for public repos only)" -ForegroundColor Yellow
}