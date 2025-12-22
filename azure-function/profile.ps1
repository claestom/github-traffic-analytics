param()

# Ensure required Az modules are loaded when the worker starts
try {
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.Storage  -ErrorAction Stop
}
catch {
    Write-Verbose "profile.ps1: Failed to import Az modules: $($_.Exception.Message)" -Verbose
}

# Optional: attempt MSI login early when a user-assigned identity client ID is present
if ($env:AZURE_CLIENT_ID) {
    try {
        Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Verbose "profile.ps1: MI login skipped: $($_.Exception.Message)" -Verbose
    }
}
else {
    Write-Verbose "profile.ps1: No managed identity configured" -Verbose
}