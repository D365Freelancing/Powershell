#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Shared module for Power Platform connection and environment resolution.

.DESCRIPTION
    Import this module in any Power Platform script to get a single
    Connect-PowerPlatform and Get-TargetEnvironment function, avoiding
    multiple login prompts when scripts are composed together.

    Usage in calling scripts:
        Import-Module -Force "$PSScriptRoot\PowerPlatformShared.psm1"

.NOTES
    Prerequisites:
      Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
      Install-Module -Name Microsoft.PowerApps.PowerShell -Scope CurrentUser
      Install-Module -Name Microsoft.Xrm.Data.PowerShell -Scope CurrentUser
#>

# Module-level flag — tracks whether Add-PowerAppsAccount has already been called
# in this session so composing scripts never prompt twice.
$script:IsConnected = $false

function Connect-PowerPlatform {
    <#
    .SYNOPSIS
        Connects to Power Platform. Safe to call multiple times — only authenticates once per session.
    #>
    [CmdletBinding()]
    param()

    if ($script:IsConnected) {
        Write-Host "[Auth] Already connected — skipping login prompt." -ForegroundColor DarkGray
        return
    }

    Write-Host "`n[Auth] Connecting to Power Platform..." -ForegroundColor Cyan
    try {
        Add-PowerAppsAccount -ErrorAction Stop
        $script:IsConnected = $true
        Write-Host "[Auth] Connected successfully.`n" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Power Platform: $_"
        exit 1
    }
}

function Get-TargetEnvironment {
    <#
    .SYNOPSIS
        Resolves a Power Platform environment by display name, GUID, or interactive picker.

    .PARAMETER EnvName
        Display name (e.g. "Production") or GUID of the environment.
        If omitted, an interactive numbered list is shown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$EnvName
    )

    Write-Host "Fetching available environments..." -ForegroundColor Cyan
    $envs = Get-AdminPowerAppEnvironment | Sort-Object DisplayName

    if ($envs.Count -eq 0) {
        Write-Error "No environments found for this account."
        exit 1
    }

    if ($EnvName) {
        # 1. Exact display name match (case-insensitive)
        $env = $envs | Where-Object { $_.DisplayName -ieq $EnvName } | Select-Object -First 1

        # 2. Fall back to GUID match
        if (-not $env) {
            $env = $envs | Where-Object { $_.EnvironmentName -ieq $EnvName } | Select-Object -First 1
        }

        if (-not $env) {
            Write-Error "Environment '$EnvName' not found by display name or GUID."
            Write-Host "`nAvailable environments:" -ForegroundColor Yellow
            $envs | ForEach-Object { Write-Host ("  {0}  ({1})" -f $_.DisplayName, $_.EnvironmentName) }
            exit 1
        }

        return $env
    }

    # No environment specified — interactive picker
    Write-Host "`nAvailable Environments:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $envs.Count; $i++) {
        Write-Host ("  [{0}] {1}  ({2})" -f $i, $envs[$i].DisplayName, $envs[$i].EnvironmentName)
    }

    $choice = Read-Host "`nEnter the number of the environment to use"
    if ($choice -notmatch '^\d+$' -or [int]$choice -ge $envs.Count) {
        Write-Error "Invalid selection."
        exit 1
    }

    return $envs[[int]$choice]
}

Export-ModuleMember -Function Connect-PowerPlatform, Get-TargetEnvironment