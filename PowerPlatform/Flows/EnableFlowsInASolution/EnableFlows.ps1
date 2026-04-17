#Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
#Install-Module -Name Microsoft.PowerApps.PowerShell -Scope CurrentUser
#Install-Module -Name Microsoft.Xrm.Data.PowerShell -Scope CurrentUser
#Set-ExecutionPolicy Bypass -Scope Process

Import-Module -Force "$PSScriptRoot\PowerPlatformShared.psm1"

$excludedFlows = "Test Flow 2"
$environment = "Dev"
$solutions = "Powershell For Power Automate ", "My Solution", "Another Solution"

Connect-PowerPlatform

$flows = .\Get-FlowsFromSolutions.ps1 `
    -EnvironmentName $environment `
    -SolutionNames $solutions

# filter out black listed flows, these are flows the script ignores
$flows = $flows | ? { $_ -notin $excludedFlows  }

# Enable
.\Enable-PowerAutomateFlows.ps1 `
    -Action Enable `
    -EnvironmentName $environment `
    -FlowNames $flows

# Ensure black listed flow are turned off
.\Enable-PowerAutomateFlows.ps1 `
    -Action Disable `
    -EnvironmentName $environment `
    -FlowNames $excludedFlows