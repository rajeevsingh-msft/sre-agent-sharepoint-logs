#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ $_ -ne [guid]::Empty })][guid]$TenantId,
    [Parameter(Mandatory)][ValidateScript({ $_ -ne [guid]::Empty })][guid]$SubscriptionId,
    [ValidatePattern('^[a-zA-Z0-9_-]{1,80}$')][string]$ResourceGroupName = 'rg-sp-sre-poc1',
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{2,13}[a-zA-Z0-9]$')][string]$VmName = 'sp-sre-poc1',
    [switch]$SignIn
)
. "$PSScriptRoot\Common.ps1"
$null = Get-Command az -ErrorAction Stop
if ($SignIn) {
    & az login --tenant $TenantId.ToString() --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) { throw 'Azure login failed. No lab context was returned.' }
}
$account = Invoke-LabAz @('account', 'show', '--subscription', $SubscriptionId.ToString())
if ($account.id -ne $SubscriptionId.ToString() -or $account.tenantId -ne $TenantId.ToString() -or
    $account.state -ne 'Enabled' -or $account.environmentName -ne 'AzureCloud') {
    throw 'Account must match the supplied tenant and enabled Azure public-cloud subscription. No lab context was returned.'
}
Write-Host "Verified account: $($account.user.name)"
Write-Host "Tenant: $TenantId; subscription: $SubscriptionId; target: $ResourceGroupName/$VmName"
Write-Host 'Review these values against your approval before continuing. The default CLI subscription was not changed.'
@{
    SubscriptionId = $SubscriptionId.ToString()
    ResourceGroupName = $ResourceGroupName
    VmName = $VmName
}
