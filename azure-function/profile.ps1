# Custom profile to avoid default MSI login errors when only a user-assigned identity is configured
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
