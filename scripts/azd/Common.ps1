#requires -Version 7.0
. "$PSScriptRoot\..\Common.ps1"

function Set-PocAzdValue {
    param([string]$Name, [string]$Value, [Parameter(Mandatory)][string]$EnvironmentName)
    & azd env set $Name $Value --environment $EnvironmentName
    if ($LASTEXITCODE -ne 0) { throw "Cannot save azd setting $Name. Stop before provisioning." }
}

function Confirm-PocAzdAction {
    param([string]$Message, [string]$Word)
    Write-Host $Message
    if ((Read-Host "Type $Word to continue") -cne $Word) {
        throw "Approval not given. No $Word action was started by this hook."
    }
}

function Get-PocAzdConfiguration {
    param([switch]$Prompt)
    $arguments = @('env', 'get-values', '--output', 'json')
    if ($env:AZURE_ENV_NAME) { $arguments += @('--environment', $env:AZURE_ENV_NAME) }
    $raw = & azd @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Cannot load the selected azd environment. Run azd up from the package root.' }
    $values = $raw -join "`n" | ConvertFrom-Json -AsHashtable
    if ($env:AZURE_ENV_NAME -and $values['AZURE_ENV_NAME'] -cne $env:AZURE_ENV_NAME) {
        throw 'The loaded azd environment differs from the hook environment. Stop before changing any target.'
    }
    $settings = @{}
    foreach ($entry in @(
        @{ Key = 'AZURE_ENV_NAME'; Label = 'Environment name (2-10 lowercase letters, digits or hyphens)'; Default = '' },
        @{ Key = 'AZURE_SUBSCRIPTION_ID'; Label = 'Approved subscription GUID'; Default = '' },
        @{ Key = 'POC1_TENANT_ID'; Label = 'Approved tenant GUID'; Default = '' },
        @{ Key = 'AZURE_LOCATION'; Label = 'Approved Azure region'; Default = 'eastus' },
        @{ Key = 'POC1_VM_SIZE'; Label = 'Approved VM size'; Default = 'Standard_D2s_v5' }
    )) {
        $value = [string]$values[$entry.Key]
        if ([string]::IsNullOrWhiteSpace($value) -and $Prompt) {
            $label = $entry.Label
            if ($entry.Default) { $label += " [$($entry.Default)]" }
            $value = Read-Host $label
            if ([string]::IsNullOrWhiteSpace($value)) { $value = $entry.Default }
        }
        if ([string]::IsNullOrWhiteSpace($value)) { throw "Missing $($entry.Key). Run the preprovision hook through azd up." }
        $settings[$entry.Key] = $value
    }
    if ($settings.AZURE_ENV_NAME -cnotmatch '^[a-z][a-z0-9-]{0,8}[a-z0-9]$') {
        throw 'Use an azd environment name of 2-10 lowercase letters, digits or hyphens, beginning with a letter and ending with a letter or digit.'
    }
    foreach ($key in @('AZURE_SUBSCRIPTION_ID', 'POC1_TENANT_ID')) {
        $id = [guid]::Empty
        if (-not [guid]::TryParse($settings[$key], [ref]$id) -or $id -eq [guid]::Empty) {
            throw "$key must be a nonempty GUID."
        }
    }
    if ($settings.AZURE_LOCATION -notmatch '^[a-z0-9]+$' -or
        $settings.POC1_VM_SIZE -notmatch '^Standard_[a-zA-Z0-9_]+$') {
        throw 'Use an Azure region code and a Standard VM SKU. No automatic region or size substitution is performed.'
    }
    $settings.ResourceGroupName = "rg-sp-sre-azd-$($settings.AZURE_ENV_NAME)"
    $settings.VmName = "sp-$($settings.AZURE_ENV_NAME)"
    $settings.ApprovedUtc = [string]$values['POC1_PROVISION_APPROVED_UTC']
    foreach ($pair in @(
        @{ Key = 'AZURE_RESOURCE_GROUP'; Expected = $settings.ResourceGroupName },
        @{ Key = 'POC1_VM_NAME'; Expected = $settings.VmName }
    )) {
        if ($values.ContainsKey($pair.Key) -and $values[$pair.Key] -ne $pair.Expected) {
            throw "$($pair.Key) conflicts with the environment-derived lab target. Use a separate azd environment; do not adopt the manual lab."
        }
    }
    if ($Prompt) {
        foreach ($key in @('AZURE_SUBSCRIPTION_ID', 'POC1_TENANT_ID', 'AZURE_LOCATION', 'POC1_VM_SIZE')) {
            Set-PocAzdValue $key $settings[$key] -EnvironmentName $settings.AZURE_ENV_NAME
        }
    }
    return $settings
}

function Assert-PocAzdResourceGroup {
    param([hashtable]$Settings)
    $subscription = $Settings.AZURE_SUBSCRIPTION_ID
    $rg = $Settings.ResourceGroupName
    $exists = Invoke-LabAz @('group', 'exists', '--subscription', $subscription, '--name', $rg)
    if ($exists -isnot [bool]) { throw 'Resource group existence was not established. Stop and inspect the target.' }
    if (-not $exists) { return }
    $group = Invoke-LabAz @('group', 'show', '--subscription', $subscription, '--name', $rg)
    foreach ($tag in @('purpose', 'environment', 'azd-env-name')) {
        $expected = switch ($tag) {
            'purpose' { 'SP-SRE-POC1' }
            'environment' { 'nonproduction' }
            'azd-env-name' { $Settings.AZURE_ENV_NAME }
        }
        if (-not $group.tags -or -not $group.tags.PSObject.Properties[$tag] -or $group.tags.$tag -ne $expected) {
            throw 'Existing resource group is not this azd lab. It will not be reused or retagged.'
        }
    }
    if ($group.location -ne $Settings.AZURE_LOCATION) {
        throw 'The existing resource group location differs. Use its original region or a new azd environment.'
    }
    $deployment = Invoke-LabAz @('deployment', 'group', 'show', '--subscription', $subscription,
        '--resource-group', $rg, '--name', 'poc1-vm')
    $vmId = "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$($Settings.VmName)"
    if ($deployment.properties.provisioningState -ne 'Succeeded' -or
        $deployment.properties.outputs.vmId.value -ne $vmId) {
        throw 'A matching successful poc1-vm deployment was not established. Inspect partial resources before recovery; no automatic adoption is allowed.'
    }
    $vm = Assert-LabVm $subscription $rg $Settings.VmName
    if ($vm.hardwareProfile.vmSize -ne $Settings.POC1_VM_SIZE) {
        throw 'Changing VM size on an existing azd lab requires separate review. Use its original size or a new environment.'
    }
    $allowed = @(
        $vmId,
        $vm.storageProfile.osDisk.managedDisk.id,
        "$vmId/extensions/RunCommandWindows",
        "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Network/networkInterfaces/$($Settings.VmName)-nic",
        "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/$($Settings.VmName)-vnet",
        "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Network/networkSecurityGroups/$($Settings.VmName)-nsg",
        "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Network/natGateways/$($Settings.VmName)-nat",
        "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Network/publicIPAddresses/$($Settings.VmName)-egress-ip"
    )
    $resources = Invoke-LabAz @('resource', 'list', '--subscription', $subscription, '--resource-group', $rg)
    foreach ($resource in $resources) {
        if ($resource.id -notin $allowed) {
            throw 'Unexpected resource in the azd lab group. Inspect the group before provisioning; shared resources are not supported.'
        }
    }
    Write-Host 'Existing azd lab matched its deployment and resource inventory. Review the what-if before approving a rerun.'
    $imageVersion = $vm.storageProfile.imageReference.version
    if ([string]::IsNullOrWhiteSpace($imageVersion) -or $imageVersion -eq 'latest') {
        throw 'The existing VM image version was not pinned. Inspect the lab before reprovisioning.'
    }
    return $imageVersion
}

function Assert-PocAzdProvisioned {
    param([hashtable]$Settings)
    $approved = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Settings.ApprovedUtc, [ref]$approved)) {
        throw 'No provisioning approval timestamp is recorded. Run azd up before guest setup.'
    }
    $deployment = Invoke-LabAz @('deployment', 'group', 'show', '--subscription', $Settings.AZURE_SUBSCRIPTION_ID,
        '--resource-group', $Settings.ResourceGroupName, '--name', 'poc1-vm')
    $deployed = [DateTimeOffset]::MinValue
    if ($deployment.properties.provisioningState -ne 'Succeeded' -or
        -not [DateTimeOffset]::TryParse($deployment.properties.timestamp, [ref]$deployed) -or $deployed -lt $approved) {
        throw 'No successful deployment after the latest approval was established. Preview alone must not initialize the guest. Inspect deployment state before recovery.'
    }
}

function Wait-PocAzdVmAgent {
    param([hashtable]$Target, [ValidateRange(1, 120)][int]$MaxAttempts = 30,
        [ValidateRange(0, 60)][int]$DelaySeconds = 10)
    $null = Assert-LabVm $Target.SubscriptionId $Target.ResourceGroupName $Target.VmName
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $view = Invoke-LabAz @('vm', 'get-instance-view', '--subscription', $Target.SubscriptionId,
            '--resource-group', $Target.ResourceGroupName, '--name', $Target.VmName)
        if ($view.PSObject.Properties['instanceView'] -and $view.instanceView -and
            $view.instanceView.PSObject.Properties['vmAgent'] -and $view.instanceView.vmAgent -and
            $view.instanceView.vmAgent.PSObject.Properties['statuses'] -and
            @($view.instanceView.vmAgent.statuses | Where-Object code -EQ 'ProvisioningState/succeeded').Count -gt 0) {
            return
        }
        if ($attempt -lt $MaxAttempts) {
            Write-Host "VM Agent is not ready yet ($attempt/$MaxAttempts). Waiting $DelaySeconds seconds..."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    throw 'VM Agent readiness timed out. No guest command was submitted. Inspect provisioning and outbound connectivity before recovery.'
}
