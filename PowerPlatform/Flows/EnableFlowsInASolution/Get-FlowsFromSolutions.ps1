#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Retrieves Power Automate flow display names from one or more solutions.

.DESCRIPTION
    Connects to Power Platform, resolves the target environment, then returns
    the display names of all flows found in the specified solutions. The output
    is a string array compatible with the -FlowNames parameter of
    Enable-PowerAutomateFlows.ps1.

.PARAMETER SolutionNames
    Array of solution display names to search within.

.PARAMETER EnvironmentName
    The Power Platform environment display name (e.g. "Production") or GUID.
    If omitted, the script lists available environments and prompts you to choose one.

.EXAMPLE
    # Get flow names and print them
    .\Get-FlowsFromSolutions.ps1 -SolutionNames "My Solution", "Another Solution"

.EXAMPLE
    # Pipe directly into Enable-PowerAutomateFlows.ps1
    $flows = .\Get-FlowsFromSolutions.ps1 -EnvironmentName "Production" -SolutionNames "My Solution"
    .\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Enable -FlowNames $flows

.EXAMPLE
    # One-liner
    .\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Enable -FlowNames (
        .\Get-FlowsFromSolutions.ps1 -EnvironmentName "Production" -SolutionNames "My Solution"
    )

.NOTES
    Prerequisites:
      Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
      Install-Module -Name Microsoft.PowerApps.PowerShell -Scope CurrentUser
      Install-Module -Name Microsoft.Xrm.Data.PowerShell -Scope CurrentUser  # for solution-component lookup
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]]$SolutionNames,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName
)

#region Helper Functions

function Connect-PowerPlatform {
    Write-Host "`n[Auth] Connecting to Power Platform..." -ForegroundColor Cyan
    try {
        Add-PowerAppsAccount -ErrorAction Stop
        Write-Host "[Auth] Connected successfully.`n" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect: $_"
        exit 1
    }
}

function Get-TargetEnvironment {
    param([string]$EnvName)

    Write-Host "Fetching available environments..." -ForegroundColor Cyan
    $envs = Get-AdminPowerAppEnvironment | Sort-Object DisplayName

    if ($envs.Count -eq 0) {
        Write-Error "No environments found for this account."
        exit 1
    }

    if ($EnvName) {
        # 1. Try exact display name match (case-insensitive)
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

function Get-FlowNamesFromSolutions {
    param (
        [string]$EnvironmentName,
        [string]$EnvironmentUrl,
        [string[]]$SolutionNames
    )

    # Fetch all flows in the environment once
    Write-Host "`nFetching all flows in environment..." -ForegroundColor Cyan
    $allFlows = Get-AdminFlow -EnvironmentName $EnvironmentName
    if (-not $allFlows) {
        Write-Warning "No flows found in this environment."
        return @()
    }
    Write-Host ("Found {0} total flow(s)." -f $allFlows.Count) -ForegroundColor Gray

    # Build a lookup: FlowName (GUID) -> DisplayName
    $flowLookup = @{}
    foreach ($flow in $allFlows) {
        $flowLookup[$flow.WorkflowEntityId] = $flow.DisplayName
    }

    # Connect to Dataverse to query solution components
    Write-Host "`nConnecting to Dataverse at '$EnvironmentUrl'..." -ForegroundColor Cyan
    try {
        $conn = Connect-CrmOnline -ServerUrl $EnvironmentUrl -ForceOAuth -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to connect to Dataverse: $_"
        exit 1
    }

    $collectedFlowNames = [System.Collections.Generic.List[string]]::new()
    $notFound           = 0

    foreach ($solutionName in $SolutionNames) {
        Write-Host ("`nSearching solution: '{0}'" -f $solutionName) -ForegroundColor Cyan

        # Look up the solution by display name
        $solutionQuery = [Microsoft.Xrm.Sdk.Query.QueryExpression]::new("solution")
        $solutionQuery.ColumnSet = [Microsoft.Xrm.Sdk.Query.ColumnSet]::new("solutionid", "friendlyname", "uniquename")
        $solutionQuery.Criteria.AddCondition("friendlyname", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $solutionName)

        $solutions = $conn.RetrieveMultiple($solutionQuery).Entities

        if ($solutions.Count -eq 0) {
            Write-Warning "  [NOT FOUND]  Solution '$solutionName' does not exist in this environment."
            $notFound++
            continue
        }

        $solution   = $solutions[0]
        $solutionId = $solution["solutionid"].ToString()

        # Query solution components of type 29 = Cloud Flow
        # https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/solutioncomponent
        $componentQuery = [Microsoft.Xrm.Sdk.Query.QueryExpression]::new("solutioncomponent")
        $componentQuery.ColumnSet = [Microsoft.Xrm.Sdk.Query.ColumnSet]::new("objectid", "componenttype")
        $componentQuery.Criteria.AddCondition("solutionid",    [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, $solutionId)
        $componentQuery.Criteria.AddCondition("componenttype", [Microsoft.Xrm.Sdk.Query.ConditionOperator]::Equal, 29)

        $components = $conn.RetrieveMultiple($componentQuery).Entities

        if ($components.Count -eq 0) {
            Write-Warning "  [NO FLOWS]   Solution '$solutionName' contains no flows."
            continue
        }

        $foundCount = 0
        foreach ($component in $components) {
            $objectId = $component["objectid"].ToString()

            if ($flowLookup.ContainsKey($objectId)) {
                $displayName = $flowLookup[$objectId]
                if (-not $collectedFlowNames.Contains($displayName)) {
                    $collectedFlowNames.Add($displayName)
                }
                Write-Host ("  [FOUND]  '{0}'" -f $displayName) -ForegroundColor Green
                $foundCount++
            }
            else {
                Write-Verbose "  Component $objectId not matched to a flow (may be inactive/hidden)."
            }
        }

        Write-Host ("  {0} flow(s) found in '{1}'." -f $foundCount, $solutionName) -ForegroundColor Gray
    }

    # Summary
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host ("  Solutions searched : {0}" -f $SolutionNames.Count)
    Write-Host ("  Solutions not found: {0}" -f $notFound) -ForegroundColor $(if ($notFound -gt 0) { "Yellow" } else { "Gray" })
    Write-Host ("  Unique flows found : {0}" -f $collectedFlowNames.Count) -ForegroundColor Green
    Write-Host ""

    return $collectedFlowNames.ToArray()
}

#endregion

#region Main

$environment = Get-TargetEnvironment -EnvName $EnvironmentName

Write-Host ("Using environment: {0}  ({1})" -f $environment.DisplayName, $environment.EnvironmentName) -ForegroundColor Cyan

# Derive the Dataverse URL from the environment's linked CDS instance
$environmentUrl = $environment.Internal.properties.linkedEnvironmentMetadata.instanceUrl
if (-not $environmentUrl) {
    Write-Error "Could not determine Dataverse URL for this environment. Ensure it has a Dataverse database."
    exit 1
}

# Return the array of flow names — this is the scriptlet's output, usable as -FlowNames
$flowNames = Get-FlowNamesFromSolutions -EnvironmentName $environment.EnvironmentName `
                                        -EnvironmentUrl $environmentUrl `
                                        -SolutionNames $SolutionNames

# Output the array so it can be captured by the caller
$flowNames

#endregion
