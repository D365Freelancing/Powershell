# Power Automate Flow Management Scripts

A set of PowerShell scripts for enabling and disabling Power Automate flows across one or more Power Platform solutions, with a single login prompt. Note - a quick overview of this PowerShell is available at https://www.d365freelancing.com/post/turn-powerautomate-flows-on-in-bulk-with-powershell

---

## Files

| File | Purpose |
|---|---|
| `PowerPlatformShared.psm1` | Shared module — handles authentication and environment resolution |
| `Get-FlowsFromSolutions.ps1` | Retrieves flow names from one or more solutions |
| `Enable-PowerAutomateFlows.ps1` | Enables or disables flows by name |
| `EnableFlows.ps1` | Sample script to Enable/Disable flows |

> **All three files must be in the same folder.** The scripts locate the shared module using `$PSScriptRoot`.

---

## Prerequisites

Install the required PowerShell modules once:

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
Install-Module -Name Microsoft.PowerApps.PowerShell -Scope CurrentUser
Install-Module -Name Microsoft.Xrm.Data.PowerShell -Scope CurrentUser
```

---

## Scripts

### `Get-FlowsFromSolutions.ps1`

Queries Dataverse to find all Cloud Flows belonging to the specified solutions and returns their display names as a `string[]`. This output is designed to feed directly into `-FlowNames` on `Enable-PowerAutomateFlows.ps1`.

**Parameters**

| Parameter | Required | Description |
|---|---|---|
| `-SolutionNames` | Yes | Array of solution display names to search |
| `-EnvironmentName` | No | Environment display name or GUID. Prompts interactively if omitted |

---

### `Enable-PowerAutomateFlows.ps1`

Enables or disables Power Automate flows by display name.

**Parameters**

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-FlowNames` | Yes | — | Array of flow display names to action |
| `-Action` | No | `Enable` | `Enable` or `Disable` |
| `-EnvironmentName` | No | — | Environment display name or GUID. Prompts interactively if omitted |

---

## Usage

### 1. Enable all flows in a solution

```powershell
$flows = .\Get-FlowsFromSolutions.ps1 -EnvironmentName "Production" -SolutionNames "My Solution"
.\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Enable -FlowNames $flows
```

### 2. Disable all flows across multiple solutions

```powershell
$flows = .\Get-FlowsFromSolutions.ps1 -EnvironmentName "Production" -SolutionNames "My Solution", "Another Solution"
.\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Disable -FlowNames $flows
```

### 3. One-liner using a subexpression

```powershell
.\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Enable -FlowNames (
    .\Get-FlowsFromSolutions.ps1 -EnvironmentName "Production" -SolutionNames "My Solution"
)
```

### 4. Let the scripts prompt you to pick an environment

Omit `-EnvironmentName` from both scripts and you will be shown a numbered list of available environments to choose from. Because authentication is shared via `PowerPlatformShared.psm1`, you will only be prompted to log in once.

```powershell
$flows = .\Get-FlowsFromSolutions.ps1 -SolutionNames "My Solution"
.\Enable-PowerAutomateFlows.ps1 -Action Enable -FlowNames $flows
```

### 5. Preview changes without applying them (`-WhatIf`)

`Enable-PowerAutomateFlows.ps1` supports PowerShell's standard `-WhatIf` flag. Use it to see what would be enabled or disabled without making any changes:

```powershell
.\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Disable -FlowNames $flows -WhatIf
```

### 6. Enable a specific list of flows (without `Get-FlowsFromSolutions`)

`Enable-PowerAutomateFlows.ps1` can be used standalone with a manually defined array:

```powershell
$flows = @(
    "Send Daily Report",
    "Sync Contacts to SharePoint",
    "Approval Notification"
)
.\Enable-PowerAutomateFlows.ps1 -EnvironmentName "Production" -Action Enable -FlowNames $flows
```

---

## How Authentication Works

Both scripts import `PowerPlatformShared.psm1`, which tracks connection state in a module-scoped flag (`$script:IsConnected`). The first script to run will trigger a single OAuth login prompt. When the second script calls `Connect-PowerPlatform`, it sees the flag is already set and skips the prompt entirely.

```
Get-FlowsFromSolutions.ps1
  └── Connect-PowerPlatform  →  [prompts for login]

Enable-PowerAutomateFlows.ps1
  └── Connect-PowerPlatform  →  [already connected, skips prompt]
```

> **Note:** The shared connection state only persists within the same PowerShell session. Opening a new terminal window will require re-authentication.

---

## Environment Resolution

Both scripts accept `-EnvironmentName` as either a **display name** or a **GUID**:

```powershell
# By display name
-EnvironmentName "Production"

# By GUID
-EnvironmentName "00000000-0000-0000-0000-000000000000"
```

If the name cannot be matched, the scripts will print a list of all available environments with their display names and GUIDs to help you identify the correct value.

---

## Output and Logging

All status messages (found, skipped, errors) are written via `Write-Host` and `Write-Warning`, which go to the console only and do not pollute the output stream. This means capturing the output of `Get-FlowsFromSolutions.ps1` into a variable will contain only the clean `string[]` of flow names, with no noise mixed in.

Each script prints a summary at the end:

```
--- Summary ---
  Solutions searched : 2
  Solutions not found: 0
  Unique flows found : 7
```

```
--- Summary ---
  Enabled  : 6
  Skipped  : 1
  Not found: 0
  Errors   : 0
```
