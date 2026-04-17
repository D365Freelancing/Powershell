#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Enables or disables Power Automate flows by name.

.DESCRIPTION
    Connects to Power Automate and enables or disables all flows whose display names
    match entries in the provided $FlowNames array.

.PARAMETER Action
    The action to perform: Enable or Disable. Defaults to Enable.

.PARAMETER EnvironmentName
    The Power Platform environment display name (e.g. "Production") or GUID.
    If omitted, the script lists available environments and prompts you to choose one.

.PARAMETER FlowNames
    Array of flow display names to enable or disable.

.EXAMPLE
    .\Manage-PowerAutomateFlows.ps1 -FlowNames "My Flow One", "My Flow Two"

.EXAMPLE
    .\Manage-PowerAutomateFlows.ps1 -Action Enable -EnvironmentName "Production" -FlowNames "My Flow One", "My Flow Two"

.EXAMPLE
    .\Manage-PowerAutomateFlows.ps1 -Action Disable -EnvironmentName "Production" -FlowNames "My Flow One", "My Flow Two"

.EXAMPLE
    $flows = @("My Flow One", "My Flow Two", "Another Flow")
    .\Manage-PowerAutomateFlows.ps1 -Action Disable -EnvironmentName "Production" -FlowNames $flows

.NOTES
    Prerequisites:
      Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
      Install-Module -Name Microsoft.PowerApps.PowerShell -Scope CurrentUser
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Enable", "Disable")]
    [string]$Action = "Enable",

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName,

    [Parameter(Mandatory = $true)]
    [string[]]$FlowNames
)

#region Helper Functions

function Enable-FlowsByName {
    param (
        [string]$EnvironmentName,
        [string[]]$Names
    )

    Write-Host "`nFetching all flows in environment '$EnvironmentName'..." -ForegroundColor Cyan
    $allFlows = Get-AdminFlow -EnvironmentName $EnvironmentName

    if (-not $allFlows) {
        Write-Warning "No flows found in this environment."
        return
    }

    Write-Host ("Found {0} total flow(s).`n" -f $allFlows.Count) -ForegroundColor Gray

    # Summary counters
    $enabled  = 0
    $notFound = 0
    $skipped  = 0
    $failed   = 0

    foreach ($name in $Names) {
        # Case-insensitive name match (handles duplicates)
        $matches = $allFlows | Where-Object { $_.DisplayName -ieq $name }

        if (-not $matches) {
            Write-Warning "  [NOT FOUND]  '$name'"
            $notFound++
            continue
        }

        foreach ($flow in $matches) {
            if ($flow.Enabled -eq $true) {
                Write-Host ("  [SKIP]       '{0}'  — already enabled." -f $flow.DisplayName) -ForegroundColor DarkGray
                $skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess($flow.DisplayName, "Enable flow")) {
                try {
                    Enable-AdminFlow -EnvironmentName $EnvironmentName -FlowName $flow.FlowName -ErrorAction Stop | Out-Null
                    Write-Host ("  [ENABLED]    '{0}'" -f $flow.DisplayName) -ForegroundColor Green
                    $enabled++
                }
                catch {
                    Write-Warning ("  [ERROR]      '{0}' — {1}" -f $flow.DisplayName, $_)
                    $failed++
                }
            }
        }
    }

    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host ("  Enabled  : {0}" -f $enabled)  -ForegroundColor Green
    Write-Host ("  Skipped  : {0}" -f $skipped)  -ForegroundColor DarkGray
    Write-Host ("  Not found: {0}" -f $notFound) -ForegroundColor Yellow
    Write-Host ("  Errors   : {0}" -f $failed)   -ForegroundColor Red
    Write-Host ""
}

function Disable-FlowsByName {
    param (
        [string]$EnvironmentName,
        [string[]]$Names
    )

    Write-Host "`nFetching all flows in environment '$EnvironmentName'..." -ForegroundColor Cyan
    $allFlows = Get-AdminFlow -EnvironmentName $EnvironmentName

    if (-not $allFlows) {
        Write-Warning "No flows found in this environment."
        return
    }

    Write-Host ("Found {0} total flow(s).`n" -f $allFlows.Count) -ForegroundColor Gray

    # Summary counters
    $disabled = 0
    $notFound = 0
    $skipped  = 0
    $failed   = 0

    foreach ($name in $Names) {
        # Case-insensitive name match (handles duplicates)
        $matches = $allFlows | Where-Object { $_.DisplayName -ieq $name }

        if (-not $matches) {
            Write-Warning "  [NOT FOUND]  '$name'"
            $notFound++
            continue
        }

        foreach ($flow in $matches) {
            if ($flow.Enabled -eq $false) {
                Write-Host ("  [SKIP]       '{0}'  — already disabled." -f $flow.DisplayName) -ForegroundColor DarkGray
                $skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess($flow.DisplayName, "Disable flow")) {
                try {
                    Disable-AdminFlow -EnvironmentName $EnvironmentName -FlowName $flow.FlowName -ErrorAction Stop | Out-Null
                    Write-Host ("  [DISABLED]   '{0}'" -f $flow.DisplayName) -ForegroundColor Yellow
                    $disabled++
                }
                catch {
                    Write-Warning ("  [ERROR]      '{0}' — {1}" -f $flow.DisplayName, $_)
                    $failed++
                }
            }
        }
    }

    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host ("  Disabled : {0}" -f $disabled) -ForegroundColor Yellow
    Write-Host ("  Skipped  : {0}" -f $skipped)  -ForegroundColor DarkGray
    Write-Host ("  Not found: {0}" -f $notFound) -ForegroundColor Yellow
    Write-Host ("  Errors   : {0}" -f $failed)   -ForegroundColor Red
    Write-Host ""
}

#endregion

#region Main

$environment = Get-TargetEnvironment -EnvName $EnvironmentName

Write-Host ("Using environment: {0}  ({1})" -f $environment.DisplayName, $environment.EnvironmentName) -ForegroundColor Cyan

switch ($Action) {
    "Enable"  { Enable-FlowsByName  -EnvironmentName $environment.EnvironmentName -Names $FlowNames }
    "Disable" { Disable-FlowsByName -EnvironmentName $environment.EnvironmentName -Names $FlowNames }
}

#endregion