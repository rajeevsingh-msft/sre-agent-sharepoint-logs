#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [string]$ResourceGroupName = 'rg-sp-sre-poc1',
    [string]$VmName = 'sp-sre-poc1',
    [string]$BastionName = 'sp-sre-poc1-vnet-bastion',
    [ValidateSet('Preview', 'Apply')][string]$Mode = 'Preview'
)
. "$PSScriptRoot\Common.ps1"

$subscription = $SubscriptionId.ToString()
$vm = Assert-LabVm $subscription $ResourceGroupName $VmName
$view = Invoke-LabAz @('vm', 'get-instance-view', '--subscription', $subscription,
    '--resource-group', $ResourceGroupName, '--name', $VmName)
if (@($view.instanceView.statuses | Where-Object code -EQ 'PowerState/running').Count -ne 1) {
    throw 'VM is not running. Inspect VM status and Resource Health before changing network access.'
}
$bastion = Invoke-LabAz @('network', 'bastion', 'show', '--subscription', $subscription,
    '--resource-group', $ResourceGroupName, '--name', $BastionName)
if ($bastion.sku.name -ne 'Developer' -or $bastion.provisioningState -ne 'Succeeded') {
    throw 'This script is only for a successfully provisioned Bastion Developer. Other SKUs need their actual Bastion subnet source.'
}
$interfaces = @($vm.networkProfile.networkInterfaces)
if ($interfaces.Count -ne 1) { throw 'Expected one lab NIC. Inspect multi-NIC routing manually.' }
$nic = Invoke-LabAz @('network', 'nic', 'show', '--subscription', $subscription,
    '--ids', $interfaces[0].id)
$configs = @($nic.ipConfigurations)
if ($configs.Count -ne 1) { throw 'Expected one lab IP configuration. Inspect actual addressing manually.' }
$config = $configs[0]
$address = $null
if (-not [Net.IPAddress]::TryParse($config.privateIPAddress, [ref]$address) -or
    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'The target NIC must have a valid private IPv4 address.'
}
if ($config.PSObject.Properties['publicIPAddress'] -and $config.publicIPAddress) {
    throw 'The lab NIC has a public IP. Review exposure before enabling RDP.'
}
$subnet = Invoke-LabAz @('network', 'vnet', 'subnet', 'show', '--subscription', $subscription,
    '--ids', $config.subnet.id)
$vnetId = $config.subnet.id -replace '/subnets/[^/]+$', ''
if (-not $bastion.PSObject.Properties['virtualNetwork'] -or
    -not $bastion.virtualNetwork -or $bastion.virtualNetwork.id -ne $vnetId) {
    throw 'Bastion Developer must reference this VM virtual network. Inspect the Bastion configuration.'
}
if (-not $subnet.PSObject.Properties['networkSecurityGroup'] -or -not $subnet.networkSecurityGroup) {
    throw 'Expected the lab subnet NSG. No access changes made.'
}
$nsgId = $subnet.networkSecurityGroup.id
if ($nic.PSObject.Properties['networkSecurityGroup'] -and $nic.networkSecurityGroup -and
    $nic.networkSecurityGroup.id -ne $nsgId) {
    throw 'A separate NIC NSG is attached. Review both effective rule sets; this script does not change multiple NSGs.'
}
$nsg = Invoke-LabAz @('network', 'nsg', 'show', '--subscription', $subscription, '--ids', $nsgId)
$inbound = @($nsg.securityRules | Where-Object direction -EQ 'Inbound')
$inbound | Sort-Object priority |
    Format-Table name, priority, access, protocol, sourceAddressPrefix, destinationAddressPrefix, destinationPortRange |
    Out-Host
$ruleName = 'Allow-BastionDeveloper-RDP'
$deny = @($inbound | Where-Object name -EQ 'DenyAllInbound')
if ($deny.Count -ne 1 -or $deny[0].access -ne 'Deny' -or $deny[0].protocol -ne '*' -or
    $deny[0].sourceAddressPrefix -ne '*' -or $deny[0].destinationAddressPrefix -ne '*' -or
    $deny[0].sourcePortRange -ne '*' -or $deny[0].destinationPortRange -ne '*' -or
    $deny[0].priority -notin 100, 200) {
    throw 'Expected the original blanket DenyAllInbound rule at 100 or 200. Review the current rules manually.'
}
if (@($inbound | Where-Object { $_.name -notin 'DenyAllInbound', $ruleName }).Count -gt 0) {
    throw 'Additional custom inbound rules exist. Review them before moving the blanket deny; no rules were changed.'
}
$source = '168.63.129.16/32'
$destination = "$($config.privateIPAddress)/32"
Write-Host "Target: $($vm.id)"
Write-Host "NSG: $nsgId"
Write-Host "Proposed: TCP $source -> ${destination}:3389; allow priority 110, blanket deny priority 200."
Write-Host 'Source is from the November 12 Bastion Developer error, not a universal Bastion source recommendation.'
Write-Host 'No guest commands, password resets, public IP creation, or firewall changes will be performed.'
if ($Mode -eq 'Preview') {
    Write-Host 'Preview only. Rerun with -Mode Apply after network-owner approval.'
    return
}
if (-not $PSCmdlet.ShouldProcess($nsgId, "Allow Bastion Developer RDP to $destination and move blanket deny to 200")) {
    return
}
$null = Invoke-LabAz @('network', 'nsg', 'rule', 'create', '--subscription', $subscription,
    '--resource-group', $nsg.resourceGroup, '--nsg-name', $nsg.name, '--name', $ruleName,
    '--priority', '110', '--direction', 'Inbound', '--access', 'Allow', '--protocol', 'Tcp',
    '--source-address-prefixes', $source, '--source-port-ranges', '*',
    '--destination-address-prefixes', $destination, '--destination-port-ranges', '3389',
    '--description', 'Approved temporary Bastion Developer RDP; screenshot-derived source; remove after use.')
# Stage the narrow exception before moving the blanket deny.
if ($deny[0].priority -ne 200) {
    $null = Invoke-LabAz @('network', 'nsg', 'rule', 'update', '--subscription', $subscription,
        '--resource-group', $nsg.resourceGroup, '--nsg-name', $nsg.name,
        '--name', 'DenyAllInbound', '--priority', '200')
}
$verified = Invoke-LabAz @('network', 'nsg', 'show', '--subscription', $subscription, '--ids', $nsgId)
$allow = @($verified.securityRules | Where-Object name -EQ $ruleName)
$finalDeny = @($verified.securityRules | Where-Object name -EQ 'DenyAllInbound')
if ($allow.Count -ne 1 -or $allow[0].priority -ne 110 -or $allow[0].access -ne 'Allow' -or
    $allow[0].direction -ne 'Inbound' -or $allow[0].protocol -ne 'Tcp' -or
    $allow[0].sourceAddressPrefix -ne $source -or $allow[0].sourcePortRange -ne '*' -or
    $allow[0].destinationAddressPrefix -ne $destination -or $allow[0].destinationPortRange -ne '3389' -or
    $finalDeny.Count -ne 1 -or $finalDeny[0].priority -ne 200 -or $finalDeny[0].access -ne 'Deny' -or
    $finalDeny[0].direction -ne 'Inbound' -or $finalDeny[0].protocol -ne '*' -or
    $finalDeny[0].sourceAddressPrefix -ne '*' -or $finalDeny[0].destinationAddressPrefix -ne '*' -or
    $finalDeny[0].sourcePortRange -ne '*' -or $finalDeny[0].destinationPortRange -ne '*') {
    throw 'Post-change rule verification failed. Inspect current NSG state; do not broaden access or retry blindly.'
}
Write-Host 'NSG settings verified. Retry VM > Connect > Bastion. Desktop connectivity is NOT yet verified.'
Write-Host 'If unreachable persists, inspect effective rules/routes and Windows RDP service/firewall; do not disable protections.'
Write-Host 'Rollback after approval: restore DenyAllInbound priority 100 FIRST, then delete Allow-BastionDeveloper-RDP.'
Write-Host 'Template redeployment can restore the original deny-at-100 configuration.'
