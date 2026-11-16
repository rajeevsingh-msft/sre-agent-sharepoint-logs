#requires -Version 7.0
[CmdletBinding()]
param()
. "$PSScriptRoot\Common.ps1"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$settings = Get-PocAzdConfiguration
$target = @{
    SubscriptionId = $settings.AZURE_SUBSCRIPTION_ID
    ResourceGroupName = $settings.ResourceGroupName
    VmName = $settings.VmName
}
$null = & "$root\scripts\Initialize-LabContext.ps1" -TenantId $settings.POC1_TENANT_ID @target
Assert-PocAzdProvisioned $settings
$null = Assert-PocAzdResourceGroup $settings
Write-Host '[4/6] Waiting for VM Agent readiness...'
Wait-PocAzdVmAgent $target
Confirm-PocAzdAction 'Initialize the synthetic fixture and approved reader using privileged SYSTEM Run Command. On reruns, proceed only after verifying no guest command is still running from an earlier attempt.' 'INITIALIZE'
$null = & "$root\scripts\Initialize-Lab.ps1" @target -Confirm:$false

Write-Host '[5/6] Testing the reader: positive must return 2; negative must return 0...'
$results = @(& "$root\scripts\Test-Lab.ps1" @target)
if ($results.Count -ne 2 -or @($results | Where-Object source -NE $target.VmName).Count -gt 0) {
    throw 'Manual tests did not establish both cases on the expected guest computer. Inspect the returned evidence before agent setup.'
}
$results | Format-Table expected, actual, partial, status -AutoSize | Out-Host
Write-Host '[6/6] Lab preparation complete. Manual VM-log retrieval passed.'
Write-Host 'SRE Agent integration is NOT yet verified. No agent access was granted.'
Write-Host 'Next: docs/Implementation-Guide.md, step 5 - Configure SRE Agent access.'
Write-Host 'Restore these nonsecret target settings in a new PowerShell terminal:'
Write-Host '$target = @{'
Write-Host "    SubscriptionId = '$($target.SubscriptionId)'"
Write-Host "    ResourceGroupName = '$($target.ResourceGroupName)'"
Write-Host "    VmName = '$($target.VmName)'"
Write-Host '}'
Write-Host 'Then follow steps 5-7 for Review-mode agent access, fresh agent investigations and separately reviewed cleanup.'
