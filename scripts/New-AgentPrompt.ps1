#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-]{1,80}$')][string]$ResourceGroupName,
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{2,13}[a-zA-Z0-9]$')][string]$VmName = 'sp-sre-poc1',
    [guid]$CorrelationId = '11111111-1111-1111-1111-111111111111'
)
$ErrorActionPreference = 'Stop'
$hash = (Get-FileHash "$PSScriptRoot\Read-UlsLab.ps1" -Algorithm SHA256).Hash
@"
Investigate only the synthetic SharePoint ULS-like fixture on this approved nonproduction Azure VM:
/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VmName

This is an on-demand source-file retrieval test, not a real SharePoint outage.
Use Review mode. First propose the exact Azure Action Run Command invocation and
payload for administrator approval. Execute only after approval.
Use command ID RunPowerShellScript and only the following PowerShell payload.
Do not install software, change files, change permissions, restart services,
enumerate other machines, or replace this with a different reader.
No RDP, SMB, WinRM, MCP connector, or Log Analytics query is needed.

--- BEGIN APPROVED POWERSHELL ---
`$ErrorActionPreference = 'Stop'
`$reader = 'C:\SP-SRE-Lab\Read-UlsLab.ps1'
if ((Get-FileHash -LiteralPath `$reader -Algorithm SHA256).Hash -ne '$hash') {
    throw 'Installed reader differs from the approved repository version.'
}
& `$reader -CorrelationId '$CorrelationId'
--- END APPROVED POWERSHELL ---

Use the script TEXT above as the VM command payload, not a path on my workstation.
Report the actual execution identity (managed identity or OBO) if available,
the exact target, successful tool trace, stdout AND stderr, queryUtc, source,
file, matchingRecordsReturned, partial and coverage.
For 11111111-1111-1111-1111-111111111111 the original fixture must return exactly 2 records.
For 33333333-3333-3333-3333-333333333333 it must return 0 records in this file only.
Do not claim healthy SharePoint, a real root cause, full-farm coverage, or continuous monitoring.
If Azure execution is unavailable or fails, report the error and stop.
Never substitute a manual result, remembered answer, or fabricated evidence.
Do not automatically retry a timeout; an administrator must first check VM command status.
"@
