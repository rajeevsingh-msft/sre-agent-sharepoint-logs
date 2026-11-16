#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidateScript({ $_ -ne [guid]::Empty })][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-]{1,80}$')][string]$ResourceGroupName,
    [ValidateNotNullOrEmpty()][string]$Location = 'eastus'
)
. "$PSScriptRoot\Common.ps1"
$exists = Invoke-LabAz @('group', 'exists', '--subscription', $SubscriptionId.ToString(),
    '--name', $ResourceGroupName)
if ($exists -isnot [bool] -or $exists) {
    throw 'Resource group is not confirmed absent. Stop and inspect the target; existing groups will not be reused or retagged.'
}
if ($PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroupName", 'Create dedicated nonproduction lab resource group')) {
    $group = Invoke-LabAz @('group', 'create', '--subscription', $SubscriptionId.ToString(),
        '--name', $ResourceGroupName, '--location', $Location,
        '--tags', 'purpose=SP-SRE-POC1', 'environment=nonproduction')
    if ($group.name -ne $ResourceGroupName -or $group.properties.provisioningState -ne 'Succeeded' -or
        $group.tags.purpose -ne 'SP-SRE-POC1' -or $group.tags.environment -ne 'nonproduction') {
        throw 'Resource group creation did not return the expected lab state. Inspect partial resources before retrying.'
    }
    $group
}
