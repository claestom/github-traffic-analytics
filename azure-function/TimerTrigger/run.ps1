# Timer trigger function for GitHub metrics collection
# Runs daily at 11:50 PM CET (23:50 CET)
# Collects clones and views data for all public repositories
# Stores results in Azure Storage Account

param($myTimer)

# Get environment variables (from Function App settings)
$GitHubToken = $env:GITHUB_TOKEN
$GitHubUsername = $env:GITHUB_USERNAME
$StorageAccountName = $env:STORAGE_ACCOUNT_NAME
$StorageContainerName = $env:STORAGE_CONTAINER_NAME
$CsvFileName = $env:CSV_FILE_NAME

# Validate required parameters
if (-not $GitHubToken) {
    Write-Error "GitHub token is required. Set GITHUB_TOKEN in Function App settings"
    exit 1
}

if (-not $GitHubUsername) {
    Write-Error "GitHub username is required. Set GITHUB_USERNAME in Function App settings"
    exit 1
}

Write-Host "===============================================================" -ForegroundColor Blue
Write-Host "       GitHub Repository Traffic Metrics - Azure Function      " -ForegroundColor White
Write-Host "===============================================================" -ForegroundColor Blue
Write-Host ""
Write-Host "Timer trigger function executed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
Write-Host "Fetching GitHub repositories for user: $GitHubUsername" -ForegroundColor Green

try {
    # GitHub API headers
    $headers = @{
        'Authorization' = "token $GitHubToken"
        'Accept' = 'application/vnd.github.v3+json'
        'User-Agent' = 'PowerShell-GitHubTrafficScraper-AzureFunction'
    }

    # Get all public repositories for the user
    $reposUrl = "https://api.github.com/users/$GitHubUsername/repos?type=owner&per_page=100"
    $repositories = Invoke-RestMethod -Uri $reposUrl -Headers $headers -Method Get
    
    $publicRepos = $repositories | Where-Object { $_.private -eq $false -and $_.owner.login -eq $GitHubUsername -and $_.fork -eq $false }
    
    Write-Host "Processing $($publicRepos.Count) repositories" -ForegroundColor Cyan
    
    # Use SAME date for all repositories: exactly 13 days ago
    $targetDate = (Get-Date).AddDays(-13).ToString('yyyy-MM-dd')
    Write-Host "Collecting data for date: $targetDate" -ForegroundColor Yellow
    
    # Get storage account context using managed identity
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    
    # Download existing CSV from storage if it exists
    $existingData = @{}
    try {
        $blobContent = Get-AzStorageBlob -Container $StorageContainerName -Blob $CsvFileName -Context $storageContext -ErrorAction SilentlyContinue
        if ($blobContent) {
            Write-Host "Found existing CSV file in storage, downloading..." -ForegroundColor Cyan
            $tempFile = [System.IO.Path]::GetTempFileName()
            Get-AzStorageBlobContent -Container $StorageContainerName -Blob $CsvFileName -Context $storageContext -Destination $tempFile -Force | Out-Null
            
            $existingCsv = Import-Csv $tempFile
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
            Remove-Item $tempFile -Force
        }
    } catch {
        Write-Host "No existing CSV found, creating new one" -ForegroundColor Yellow
    }
    
    $newDayData = @{}
    $totalViewsForDay = 0
    $totalClonesForDay = 0
    
    foreach ($repo in $publicRepos) {
        Write-Host "Processing repository: $($repo.name)" -ForegroundColor Yellow
        
        try {
            # Get traffic views (last 14 days)
            $viewsUrl = "https://api.github.com/repos/$GitHubUsername/$($repo.name)/traffic/views"
            $viewsData = Invoke-RestMethod -Uri $viewsUrl -Headers $headers -Method Get
            
            # Get traffic clones (last 14 days)  
            $clonesUrl = "https://api.github.com/repos/$GitHubUsername/$($repo.name)/traffic/clones"
            $clonesData = Invoke-RestMethod -Uri $clonesUrl -Headers $headers -Method Get
            
            $viewCount = 0
            $cloneCount = 0
            
            # Look for views data for the specific target date (13 days ago)
            if ($viewsData.views.Count -gt 0) {
                $targetViewDay = $viewsData.views | Where-Object { 
                    [DateTime]::Parse($_.timestamp).ToString('yyyy-MM-dd') -eq $targetDate 
                }
                if ($targetViewDay) {
                    $viewCount = $targetViewDay.count
                }
            }
            
            # Look for clones data for the specific target date (13 days ago)
            if ($clonesData.clones.Count -gt 0) {
                $targetCloneDay = $clonesData.clones | Where-Object { 
                    [DateTime]::Parse($_.timestamp).ToString('yyyy-MM-dd') -eq $targetDate 
                }
                if ($targetCloneDay) {
                    $cloneCount = $targetCloneDay.count
                }
            }
            
            # Format data as "views(clones)"
            $formattedData = "$viewCount($cloneCount)"
            $newDayData[$repo.name] = $formattedData
            
            $totalViewsForDay += $viewCount
            $totalClonesForDay += $cloneCount
            
            Write-Host "  Views = $viewCount & Clones = $cloneCount" -ForegroundColor Gray
            
            # Rate limiting - GitHub allows 5000 requests per hour
            Start-Sleep -Milliseconds 100
            
        } catch {
            Write-Warning "Failed to get traffic data for repository '$($repo.name)': $($_.Exception.Message)"
            Write-Host "  Views = 0 & Clones = 0" -ForegroundColor Gray
            $newDayData[$repo.name] = "0(0)"
        }
    }
    
    # Build the final data structure
    $allRepositories = @($publicRepos.name) + @("TOTAL")
    $allDates = @()
    
    # Get all unique dates from existing data and add new date
    if ($existingData.Count -gt 0) {
        $existingDates = $existingData.Values | ForEach-Object { $_.Keys } | Sort-Object | Get-Unique
        $allDates += $existingDates
    }
    if ($targetDate -notin $allDates) {
        $allDates += $targetDate
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
                    $repoData = if ($date -eq $targetDate -and $newDayData.ContainsKey($repo)) {
                        $newDayData[$repo]
                    } elseif ($existingData.ContainsKey($repo) -and $existingData[$repo].ContainsKey($date)) {
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
                $repoData = if ($date -eq $targetDate -and $newDayData.ContainsKey($repoName)) {
                    $newDayData[$repoName]
                } elseif ($existingData.ContainsKey($repoName) -and $existingData[$repoName].ContainsKey($date)) {
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
    
    # Export to temporary CSV file
    $tempCsvFile = [System.IO.Path]::GetTempFileName()
    $outputData | Export-Csv -Path $tempCsvFile -NoTypeInformation -Encoding UTF8
    
    # Upload CSV to Azure Storage
    Write-Host "Uploading CSV to Azure Storage..." -ForegroundColor Cyan
    Set-AzStorageBlobContent -File $tempCsvFile -Container $StorageContainerName -Blob $CsvFileName -Context $storageContext -Force | Out-Null
    
    # Cleanup
    Remove-Item $tempCsvFile -Force
    
    Write-Host ""
    Write-Host "Results saved to: $($StorageContainerName)/$($CsvFileName)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary for ${targetDate}:" -ForegroundColor Cyan
    Write-Host "  Total Repositories: $($publicRepos.Count)" -ForegroundColor White
    Write-Host "  Total Views: $totalViewsForDay" -ForegroundColor White  
    Write-Host "  Total Clones: $totalClonesForDay" -ForegroundColor White
    Write-Host ""
    Write-Host "Function execution completed successfully at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to fetch repository data: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.Exception.StackTrace)" -ForegroundColor Red
    exit 1
}
