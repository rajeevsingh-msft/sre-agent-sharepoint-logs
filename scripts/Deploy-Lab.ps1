#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-]{1,80}$')][string]$ResourceGroupName,
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{2,13}[a-zA-Z0-9]$')][string]$VmName = 'sp-sre-poc1',
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })][string]$Location = 'eastus',
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })][string]$VmSize = 'Standard_D2s_v5',
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9]{3,19}$')][string]$AdminUsername = 'pocadmin',
    [ValidateSet('Preview', 'Deploy')][string]$Mode = 'Preview'
)
. "$PSScriptRoot\Common.ps1"
$check = & "$PSScriptRoot\Test-Preflight.ps1" -SubscriptionId $SubscriptionId -Location $Location -VmSize $VmSize
$group = Invoke-LabAz @('group', 'show', '--subscription', $SubscriptionId.ToString(), '--name', $ResourceGroupName)
if ($null -eq $group.tags -or -not $group.tags.PSObject.Properties['purpose'] -or
    $group.tags.purpose -ne 'SP-SRE-POC1') {
    throw 'Use a dedicated resource group tagged purpose=SP-SRE-POC1; do not deploy into an existing application resource group.'
}
$arguments = @('--subscription', $SubscriptionId.ToString(), '--resource-group', $ResourceGroupName,
    '--name', "$VmName-infra", '--template-file', "$PSScriptRoot\..\infra\main.bicep",
    '--parameters', "vmName=$VmName", "location=$Location", "vmSize=$VmSize",
    "adminUsername=$AdminUsername", "imageVersion=$($check.imageVersion)", '--only-show-errors')
Write-Host 'Azure CLI will securely prompt for adminPassword for each operation. Do not put it in command arguments or files.'
& az deployment group validate @arguments --output none
if ($LASTEXITCODE -ne 0) { throw 'ARM validation failed. Nothing was deployed.' }
& az deployment group what-if @arguments
if ($LASTEXITCODE -ne 0) { throw 'ARM what-if failed. Nothing was deployed.' }
if ($Mode -eq 'Deploy' -and $PSCmdlet.ShouldProcess("$ResourceGroupName/$VmName", 'Deploy VM, OS disk, NAT gateway and network resources (billable)')) {
    & az deployment group create @arguments --output json
    if ($LASTEXITCODE -ne 0) { throw 'Deployment failed. Inspect the named deployment and partial resources before retrying.' }
}
