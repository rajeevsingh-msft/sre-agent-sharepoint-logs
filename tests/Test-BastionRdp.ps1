#requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:BastionRdpTest = @{
    subscription = '00000000-0000-0000-0000-000000000001'
    prefix = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-sp-sre-poc1/providers'
}
$global:BastionRdpTest.nsgId = "$($global:BastionRdpTest.prefix)/Microsoft.Network/networkSecurityGroups/sp-sre-poc1-nsg"
$global:BastionRdpTest.vnetId = "$($global:BastionRdpTest.prefix)/Microsoft.Network/virtualNetworks/sp-sre-poc1-vnet"

function Reset-Fixture {
    $global:BastionRdpTest.writes = [Collections.Generic.List[string]]::new()
    $global:BastionRdpTest.denyPriority = 100
    $global:BastionRdpTest.allow = $null
    $global:BastionRdpTest.sku = 'Developer'
    $global:BastionRdpTest.extraNicNsg = $false
    $global:BastionRdpTest.extraRule = $false
    $global:BastionRdpTest.failCreate = $false
    $global:BastionRdpTest.badVerification = $false
}

function az {
    $global:LASTEXITCODE = 0
    $state = $global:BastionRdpTest
    $command = $args -join ' '
    $result = switch -Regex ($command) {
        '^vm show ' { @{
            id = "$($state.prefix)/Microsoft.Compute/virtualMachines/sp-sre-poc1"
            tags = @{ purpose = 'SP-SRE-POC1'; environment = 'nonproduction' }
            storageProfile = @{ osDisk = @{ osType = 'Windows' } }
            networkProfile = @{ networkInterfaces = @(@{ id = "$($state.prefix)/Microsoft.Network/networkInterfaces/sp-sre-poc1-nic" }) }
        }; break }
        '^vm get-instance-view ' { @{ instanceView = @{ statuses = @(@{ code = 'PowerState/running' }) } }; break }
        '^network bastion show ' { @{
            sku = @{ name = $state.sku }; provisioningState = 'Succeeded'
            virtualNetwork = @{ id = $state.vnetId }
        }; break }
        '^network nic show ' { @{
            networkSecurityGroup = $(if ($state.extraNicNsg) { @{ id = 'another-nsg' } } else { $null })
            ipConfigurations = @(@{ privateIPAddress = '10.74.0.4'; publicIPAddress = $null
                subnet = @{ id = "$($state.vnetId)/subnets/lab" } })
        }; break }
        '^network vnet subnet show ' { @{ networkSecurityGroup = @{ id = $state.nsgId } }; break }
        '^network nsg rule create ' {
            foreach ($expected in @('--priority 110', '--protocol Tcp',
                '--source-address-prefixes 168.63.129.16/32', '--source-port-ranges *',
                '--destination-address-prefixes 10.74.0.4/32', '--destination-port-ranges 3389')) {
                if (-not $command.Contains($expected)) { throw "Missing narrow rule argument: $expected" }
            }
            $state.writes.Add('create')
            if ($state.failCreate) { $global:LASTEXITCODE = 1; return }
            $state.allow = @{
                name = 'Allow-BastionDeveloper-RDP'; priority = 110; access = 'Allow'
                direction = 'Inbound'; protocol = 'Tcp'; sourceAddressPrefix = '168.63.129.16/32'
                sourcePortRange = '*'; destinationAddressPrefix = '10.74.0.4/32'; destinationPortRange = '3389'
            }
            $state.allow; break
        }
        '^network nsg rule update ' {
            $state.writes.Add('update'); $state.denyPriority = 200
            @{ name = 'DenyAllInbound' }; break
        }
        '^network nsg show ' {
            $rules = @(@{ name = 'DenyAllInbound'; priority = $state.denyPriority; access = 'Deny'
                direction = 'Inbound'; protocol = '*'; sourceAddressPrefix = '*'; destinationAddressPrefix = '*'
                sourcePortRange = '*'; destinationPortRange = '*' })
            if ($state.allow) {
                if ($state.badVerification) { $state.allow.destinationPortRange = '22' }
                $rules += $state.allow
            }
            if ($state.extraRule) { $rules += @{ name = 'UnexpectedAllow'; direction = 'Inbound'; priority = 150 } }
            @{ name = 'sp-sre-poc1-nsg'; resourceGroup = 'rg-sp-sre-poc1'; securityRules = $rules }; break
        }
        default { throw "Unexpected CLI command: $command" }
    }
    $result | ConvertTo-Json -Depth 20 -Compress
}

function Invoke-Subject {
    param([string]$Mode = 'Preview', [switch]$DryRun)
    & "$PSScriptRoot\..\scripts\Enable-BastionRdp.ps1" -SubscriptionId $global:BastionRdpTest.subscription `
        -Mode $Mode -Confirm:$false -WhatIf:$DryRun | Out-Null
}
function Assert-Failure {
    param([string]$Expected)
    $message = $null
    try { Invoke-Subject -Mode Apply } catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notlike "*$Expected*") { throw "Expected failure '$Expected'; received '$message'." }
}

Reset-Fixture
Invoke-Subject
if ($global:BastionRdpTest.writes.Count) { throw 'Preview mutated Azure.' }
Reset-Fixture
Invoke-Subject -Mode Apply -DryRun
if ($global:BastionRdpTest.writes.Count) { throw 'WhatIf mutated Azure.' }
Reset-Fixture
Invoke-Subject -Mode Apply
if (($global:BastionRdpTest.writes -join ',') -ne 'create,update') { throw 'Narrow allow must be created before moving deny.' }
$global:BastionRdpTest.writes.Clear()
Invoke-Subject -Mode Apply
if (($global:BastionRdpTest.writes -join ',') -ne 'create') { throw 'Repeat apply unexpectedly moved the deny again.' }
Reset-Fixture
$global:BastionRdpTest.sku = 'Standard'
Assert-Failure 'only for'
if ($global:BastionRdpTest.writes.Count) { throw 'Wrong SKU mutated Azure.' }
Reset-Fixture
$global:BastionRdpTest.extraNicNsg = $true
Assert-Failure 'separate NIC NSG'
if ($global:BastionRdpTest.writes.Count) { throw 'Unexpected NIC NSG mutated Azure.' }
Reset-Fixture
$global:BastionRdpTest.extraRule = $true
Assert-Failure 'Additional custom inbound'
if ($global:BastionRdpTest.writes.Count) { throw 'Unexpected rules mutated Azure.' }
Reset-Fixture
$global:BastionRdpTest.failCreate = $true
Assert-Failure 'Azure CLI failed'
if (($global:BastionRdpTest.writes -join ',') -ne 'create' -or $global:BastionRdpTest.denyPriority -ne 100) { throw 'Failed allow creation moved deny.' }
Reset-Fixture
$global:BastionRdpTest.badVerification = $true
Assert-Failure 'verification failed'
Write-Host 'PASS: 9 mocked preview, WhatIf, apply/reapply, guard, ordering, and failure checks. No Azure calls.'
