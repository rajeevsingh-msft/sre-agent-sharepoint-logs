#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })][string]$Location = 'eastus',
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })][string]$VmSize = 'Standard_D2s_v5'
)
. "$PSScriptRoot\Common.ps1"
$subscription = $SubscriptionId.ToString()
$account = Invoke-LabAz @('account', 'show', '--subscription', $subscription)
if ($account.state -ne 'Enabled' -or $account.environmentName -ne 'AzureCloud') {
    throw 'This package targets an enabled Azure public-cloud subscription only.'
}
foreach ($provider in @('Microsoft.Compute', 'Microsoft.Network')) {
    $state = Invoke-LabAz @('provider', 'show', '--subscription', $subscription, '--namespace', $provider)
    if ($state.registrationState -ne 'Registered') {
        throw "$provider registration state is '$($state.registrationState)', not Registered. Ask the subscription owner to register it, then rerun."
    }
}
$skus = Invoke-LabAz @('vm', 'list-skus', '--subscription', $subscription,
    '--location', $Location, '--size', $VmSize, '--all')
$matches = @($skus | Where-Object { $_.name -eq $VmSize -and $_.resourceType -eq 'virtualMachines' })
if ($matches.Count -ne 1) { throw "VM size $VmSize is not uniquely available in $Location." }
$sku = $matches[0]
if (@($sku.restrictions | Where-Object type -EQ 'Location').Count -gt 0) {
    throw "VM size $VmSize has a location/subscription restriction in $Location."
}
$vcpus = @($sku.capabilities | Where-Object name -EQ 'vCPUs')
$generations = @($sku.capabilities | Where-Object name -EQ 'HyperVGenerations')
$trustedLaunchDisabled = @($sku.capabilities | Where-Object name -EQ 'TrustedLaunchDisabled')
if ($vcpus.Count -ne 1 -or $generations.Count -ne 1 -or
    $generations[0].value -notmatch 'V2' -or
    ($trustedLaunchDisabled.Count -gt 0 -and $trustedLaunchDisabled[0].value -eq 'True')) {
    throw 'SKU does not establish vCPU count and Trusted Launch / Generation 2 compatibility.'
}
$usage = Invoke-LabAz @('vm', 'list-usage', '--subscription', $subscription, '--location', $Location)
foreach ($quotaName in @('cores', $sku.family)) {
    $quota = @($usage | Where-Object { $_.name.value -eq $quotaName })
    if ($quota.Count -ne 1 -or
        [int]$quota[0].currentValue + [int]$vcpus[0].value -gt [int]$quota[0].limit) {
        throw "Insufficient or unverified $quotaName vCPU quota in $Location."
    }
    if (($quota[0].currentValue + [int]$vcpus[0].value) -gt (0.8 * $quota[0].limit)) {
        Write-Warning "$quotaName quota will exceed 80% after deploying this VM."
    }
}
$image = Invoke-LabAz @('vm', 'image', 'show', '--subscription', $subscription,
    '--location', $Location, '--urn', 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest')
if ([string]::IsNullOrWhiteSpace($image.name) -or $image.name -eq 'latest' -or
    $image.hyperVGeneration -ne 'V2') {
    throw 'Could not resolve a published Generation 2 Windows image version.'
}
[pscustomobject]@{
    subscriptionId = $subscription
    location = $Location
    vmSize = $VmSize
    imageVersion = $image.name
    checkedUtc = [DateTime]::UtcNow.ToString('o')
    limitation = 'Quota/SKU/image checks are not a capacity reservation or policy/deployment guarantee.'
}
