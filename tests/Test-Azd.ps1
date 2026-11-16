#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$helper = "$root\scripts\azd\Common.ps1"
$pre = "$root\scripts\azd\preprovision.ps1"
$post = "$root\scripts\azd\postprovision.ps1"
$script:passed = 0
$previousState = Get-Variable PocAzdTestState -Scope Global -ErrorAction SilentlyContinue
if ($previousState) { throw 'PocAzdTestState already exists; run this test in a separate PowerShell process.' }
$originalEnvironmentName = $env:AZURE_ENV_NAME
$env:AZURE_ENV_NAME = 'poc1-auto'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $failure = $null
    try { $null = & $Action } catch { $failure = $_ }
    Assert-True ($null -ne $failure) 'Expected an explicit failure.'
    if ($Pattern) {
        Assert-True ($failure.Exception.Message -like "*$Pattern*") "Unexpected failure: $($failure.Exception.Message)"
    }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    $global:PocAzdTestState = @{
        Values = @{
            AZURE_ENV_NAME = 'poc1-auto'
            AZURE_SUBSCRIPTION_ID = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            POC1_TENANT_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            AZURE_LOCATION = 'eastus2'
            POC1_VM_SIZE = 'Standard_D2s_v6'
            POC1_PROVISION_APPROVED_UTC = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o')
        }
        Calls = [Collections.Generic.List[string]]::new()
        Mode = 'success'
        Exists = $false
        Answers = [Collections.Generic.Queue[string]]::new()
        AgentReads = 0
        Runs = 0
        ProviderReads = 0
    }
    foreach ($answer in @('TARGET', 'PROVISION', 'INITIALIZE')) {
        $global:PocAzdTestState.Answers.Enqueue($answer)
    }
    try { & $Action }
    catch { throw "Test '$Name' failed: $($_.Exception.Message)" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Read-Host {
    param([string]$Prompt)
    $state = $global:PocAzdTestState
    if ($state.Answers.Count -eq 0) { throw "Unexpected prompt: $Prompt" }
    return $state.Answers.Dequeue()
}
function azd {
    $state = $global:PocAzdTestState
    $state.Calls.Add("azd $($args -join ' ')")
    $global:LASTEXITCODE = 0
    if ($state.Mode -eq 'azd-failure') { $global:LASTEXITCODE = 1; return }
    if ($args[0] -eq 'env' -and $args[1] -eq 'get-values') {
        return ($state.Values | ConvertTo-Json)
    }
    if ($args[0] -eq 'env' -and $args[1] -eq 'set') {
        $state.Values[$args[2]] = $args[3]
        return
    }
    throw "Unexpected azd command: $($args -join ' ')"
}
function az {
    $a = @($args)
    $state = $global:PocAzdTestState
    $state.Calls.Add("az $($a -join ' ')")
    $global:LASTEXITCODE = 0
    $subscription = $state.Values.AZURE_SUBSCRIPTION_ID
    $rg = "rg-sp-sre-azd-$($state.Values.AZURE_ENV_NAME)"
    $vm = "sp-$($state.Values.AZURE_ENV_NAME)"
    $vmId = "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$vm"
    if ($a[0] -eq 'bicep') { return 'Bicep CLI version <TEST>' }
    if ($a[0] -eq 'login') { return }
    if ($a[0] -eq 'account') {
        $account = @{
            id = $subscription; tenantId = $state.Values.POC1_TENANT_ID
            state = 'Enabled'; environmentName = 'AzureCloud'; user = @{ name = '<TEST-OPERATOR>' }
        }
        if ($state.Mode -eq 'wrong-tenant') { $account.tenantId = 'cccccccc-cccc-cccc-cccc-cccccccccccc' }
        if ($state.Mode -eq 'wrong-cloud') { $account.environmentName = 'AzureUSGovernment' }
        if ($a[1] -eq 'list') {
            if ($state.Mode -eq 'login-needed') { return '[]' }
            return (ConvertTo-Json -InputObject @($account) -Depth 4)
        }
        return ($account | ConvertTo-Json)
    }
    if ($a[0] -eq 'provider') {
        if ($a[1] -eq 'register') {
            if ($state.Mode -eq 'register-failure') { $global:LASTEXITCODE = 1 }
            return
        }
        $state.ProviderReads++
        $status = 'Registered'
        if ($state.Mode -in @('missing-provider', 'register-failure') -and $state.ProviderReads -eq 1) {
            $status = 'NotRegistered'
        }
        if ($state.Mode -eq 'unexpected-provider') { $status = 'Unregistering' }
        return (@{ registrationState = $status } | ConvertTo-Json)
    }
    if ($a[0] -eq 'group') {
        if ($a[1] -eq 'exists') {
            if ($state.Mode -eq 'invalid-exists') { return '"false"' }
            return ($state.Exists | ConvertTo-Json)
        }
        $tags = @{ purpose = 'SP-SRE-POC1'; environment = 'nonproduction'; 'azd-env-name' = $state.Values.AZURE_ENV_NAME }
        if ($state.Mode -eq 'foreign-group') { $tags.purpose = 'other' }
        $location = if ($state.Mode -eq 'region-change') { 'westus' } else { $state.Values.AZURE_LOCATION }
        return (@{ tags = $tags; location = $location } | ConvertTo-Json)
    }
    if ($a[0] -eq 'deployment') {
        if ($a[1] -eq 'sub') {
            Assert-True ($a[2] -eq 'what-if') 'Hooks must not create deployments.'
            if ($state.Mode -eq 'preview-failure') { $global:LASTEXITCODE = 1 }
            return
        }
        $deploymentVmId = if ($state.Mode -eq 'wrong-deployment') { 'other' } else { $vmId }
        $status = if ($state.Mode -eq 'partial-group') { 'Failed' } else { 'Succeeded' }
        $timestamp = if ($state.Mode -eq 'preview-only') {
            [DateTimeOffset]::UtcNow.AddMinutes(-10).ToString('o')
        } else { [DateTimeOffset]::UtcNow.ToString('o') }
        return (@{ properties = @{
            provisioningState = $status
            timestamp = $timestamp
            outputs = @{ vmId = @{ value = $deploymentVmId } }
        } } | ConvertTo-Json -Depth 6)
    }
    if ($a[0] -eq 'resource') {
        $resources = @(@{ id = $vmId })
        if ($state.Mode -eq 'extra-resource') { $resources += @{ id = "$vmId/unexpected" } }
        return (ConvertTo-Json -InputObject $resources -Depth 4)
    }
    if ($a[0] -eq 'vm' -and $a[1] -eq 'list-skus') {
        return (ConvertTo-Json -InputObject @(@{
            name = $state.Values.POC1_VM_SIZE; resourceType = 'virtualMachines'; family = 'StandardDsv6Family'
            restrictions = @()
            capabilities = @(@{ name = 'vCPUs'; value = '2' }, @{ name = 'HyperVGenerations'; value = 'V2' })
        }) -Depth 6)
    }
    if ($a[0] -eq 'vm' -and $a[1] -eq 'list-usage') {
        return (ConvertTo-Json -InputObject @(
            @{ name = @{ value = 'cores' }; currentValue = 0; limit = 100 },
            @{ name = @{ value = 'StandardDsv6Family' }; currentValue = 0; limit = 100 }
        ) -Depth 4)
    }
    if ($a[0] -eq 'vm' -and $a[1] -eq 'image') {
        return '{"name":"20348.9999.1","hyperVGeneration":"V2"}'
    }
    if ($a[0] -eq 'vm' -and $a[1] -eq 'show') {
        $size = if ($state.Mode -eq 'size-change') { 'Standard_D4s_v6' } else { $state.Values.POC1_VM_SIZE }
        return (@{
            tags = @{ purpose = 'SP-SRE-POC1'; environment = 'nonproduction' }
            storageProfile = @{
                osDisk = @{ osType = 'Windows'; managedDisk = @{ id = "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Compute/disks/os" } }
                imageReference = @{ version = '20348.1111.1' }
            }
            hardwareProfile = @{ vmSize = $size }
        } | ConvertTo-Json -Depth 6)
    }
    if ($a[0] -eq 'vm' -and $a[1] -eq 'get-instance-view') {
        $state.AgentReads++
        if ($state.Mode -eq 'agent-not-ready' -or
            ($state.Mode -eq 'agent-delayed' -and $state.AgentReads -eq 1)) {
            return '{"instanceView":{}}'
        }
        return '{"instanceView":{"statuses":[{"code":"PowerState/running"},{"code":"ProvisioningState/succeeded"}],"vmAgent":{"statuses":[{"code":"ProvisioningState/succeeded"}]}}}'
    }
    if (($a[0..2] -join ' ') -eq 'vm extension list') {
        return '[]'
    }
    if ($a[0] -eq 'vm' -and $a[1] -eq 'run-command') {
        $state.Runs++
        if ($state.Mode -eq 'guest-failure') { $global:LASTEXITCODE = 1; return }
        $hash = (Get-FileHash "$root\scripts\Read-UlsLab.ps1" -Algorithm SHA256).Hash
        if ($state.Runs -eq 1) {
            $body = @{ kind = 'uls-lab-initialized'; synthetic = $true; readerSha256 = $hash }
        } else {
            $count = if ($state.Runs -eq 2) { 2 } else { 0 }
            if ($state.Mode -eq 'wrong-count') { $count = 7 }
            $id = if ($state.Runs -eq 2) { '11111111-1111-1111-1111-111111111111' } else { '33333333-3333-3333-3333-333333333333' }
            $body = @{
                kind = 'uls-lab-evidence'; synthetic = $true; source = $vm
                file = 'C:\SP-SRE-Lab\Synthetic-ULS.log'; correlationId = $id
                queryUtc = [DateTime]::UtcNow.ToString('o')
                matchingRecordsReturned = $count; partial = $false
                linesRead = 4; coverage = 'One synthetic file; mocked complete scan.'
                readerSha256 = $hash
                evidence = @(for ($i = 1; $i -le $count; $i++) {
                    @{ lineNumber = $i; fragment = 'Synthetic test evidence' }
                })
            }
            if ($state.Mode -eq 'wrong-source') { $body.source = 'other-vm' }
            if ($state.Mode -eq 'partial-result') { $body.partial = $true }
        }
        return (@{ value = @(
            @{ code = 'ComponentStatus/StdOut/succeeded'; message = ($body | ConvertTo-Json -Compress) },
            @{ code = 'ComponentStatus/StdErr/succeeded'; message = '' }
        ) } | ConvertTo-Json -Depth 6)
    }
    throw "Unexpected mocked Azure CLI command: $($a -join ' ')"
}

try {
    . $helper
    Test-Case 'All azd PowerShell scripts parse' {
        foreach ($file in Get-ChildItem "$root\scripts\azd" -Filter '*.ps1') {
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            Assert-True ($errors.Count -eq 0) "Syntax error in $($file.Name)"
        }
    }
    Test-Case 'Environment settings derive a separate RG and Windows-safe VM' {
        $settings = Get-PocAzdConfiguration
        Assert-True ($settings.ResourceGroupName -eq 'rg-sp-sre-azd-poc1-auto' -and
            $settings.VmName -eq 'sp-poc1-auto' -and $settings.VmName.Length -le 15) 'Wrong derived target.'
        Assert-True ($global:PocAzdTestState.Calls.Count -eq 1) 'Configuration lookup mutated state.'
    }
    Test-Case 'Hook environment selection is explicit for reads and writes' {
        $null = Get-PocAzdConfiguration -Prompt
        foreach ($call in $global:PocAzdTestState.Calls) {
            Assert-True ($call -like '*--environment poc1-auto') 'azd used the default environment instead of the selected hook environment.'
        }
    }
    Test-Case 'Different loaded environment is rejected before settings are saved' {
        $global:PocAzdTestState.Values.AZURE_ENV_NAME = 'other-env'
        Assert-Throws { Get-PocAzdConfiguration -Prompt } 'differs from the hook'
        Assert-True ($global:PocAzdTestState.Calls.Count -eq 1) 'Wrong environment was modified.'
    }
    foreach ($name in @('', 'A-invalid', 'too-long-environment', 'bad-', 'a')) {
        Test-Case "Reject invalid environment name '$name'" {
            $global:PocAzdTestState.Values.AZURE_ENV_NAME = $name
            Assert-Throws { Get-PocAzdConfiguration } ''
        }
    }
    foreach ($key in @('AZURE_SUBSCRIPTION_ID', 'POC1_TENANT_ID', 'AZURE_LOCATION', 'POC1_VM_SIZE')) {
        Test-Case "Reject blank $key" {
            $global:PocAzdTestState.Values[$key] = ' '
            Assert-Throws { Get-PocAzdConfiguration } $key
        }
    }
    Test-Case 'Reject empty GUID' {
        $global:PocAzdTestState.Values.AZURE_SUBSCRIPTION_ID = [guid]::Empty.ToString()
        Assert-Throws { Get-PocAzdConfiguration } 'nonempty GUID'
    }
    Test-Case 'Reject adopting the manual lab through environment outputs' {
        $global:PocAzdTestState.Values.AZURE_RESOURCE_GROUP = 'rg-sp-sre-poc1'
        Assert-Throws { Get-PocAzdConfiguration } 'conflicts'
    }
    Test-Case 'azd configuration failure is explicit' {
        $global:PocAzdTestState.Mode = 'azd-failure'
        Assert-Throws { Get-PocAzdConfiguration } 'Cannot load'
    }
    Test-Case 'Declined action fails closed' {
        $global:PocAzdTestState.Answers.Clear()
        $global:PocAzdTestState.Answers.Enqueue('no')
        Assert-Throws { Confirm-PocAzdAction 'Test' 'PROVISION' } 'Approval not given'
    }
    Test-Case 'Preprovision checks then previews without deploying or granting roles' {
        & $pre
        $calls = $global:PocAzdTestState.Calls
        Assert-True (@($calls | Where-Object { $_ -like 'az deployment sub what-if *' }).Count -eq 1) 'Missing single preview.'
        Assert-True (@($calls | Where-Object { $_ -match 'deployment .* create|role assignment|group create|run-command' }).Count -eq 0) 'Hook deployed or granted access.'
        Assert-True ($global:PocAzdTestState.Values.POC1_IMAGE_VERSION -eq '20348.9999.1') 'Resolved image not persisted.'
        Assert-True (@($calls | Where-Object { $_ -match 'adminPassword|password=' }).Count -eq 0) 'Password appeared in arguments.'
    }
    Test-Case 'Provider registration requires explicit approval' {
        $global:PocAzdTestState.Mode = 'missing-provider'
        $global:PocAzdTestState.Answers.Clear()
        foreach ($word in @('TARGET', 'REGISTER', 'PROVISION')) { $global:PocAzdTestState.Answers.Enqueue($word) }
        & $pre
        Assert-True (@($global:PocAzdTestState.Calls | Where-Object { $_ -like 'az provider register *' }).Count -eq 1) 'Expected one approved registration.'
    }
    Test-Case 'Declined provider registration stops before mutation' {
        $global:PocAzdTestState.Mode = 'missing-provider'
        $global:PocAzdTestState.Answers.Clear()
        foreach ($word in @('TARGET', 'no')) { $global:PocAzdTestState.Answers.Enqueue($word) }
        Assert-Throws { & $pre } 'Approval not given'
        Assert-True (@($global:PocAzdTestState.Calls | Where-Object { $_ -like 'az provider register *' }).Count -eq 0) 'Provider changed without approval.'
    }
    foreach ($mode in @('wrong-tenant', 'wrong-cloud', 'unexpected-provider', 'preview-failure')) {
        Test-Case "Preprovision stops on $mode" {
            $global:PocAzdTestState.Mode = $mode
            Assert-Throws { & $pre } ''
        }
    }
    Test-Case 'Registered providers are never changed' {
        & $pre
        Assert-True (@($global:PocAzdTestState.Calls | Where-Object { $_ -like 'az provider register *' }).Count -eq 0) 'Registered provider changed.'
    }
    Test-Case 'Fresh group is accepted without creating it in the hook' {
        $settings = Get-PocAzdConfiguration
        $null = Assert-PocAzdResourceGroup $settings
        Assert-True (@($global:PocAzdTestState.Calls | Where-Object { $_ -like '*group create*' }).Count -eq 0) 'Hook created RG.'
    }
    Test-Case 'Matching existing deployment retains its pinned image' {
        $global:PocAzdTestState.Exists = $true
        & $pre
        Assert-True ($global:PocAzdTestState.Values.POC1_IMAGE_VERSION -eq '20348.1111.1') 'Rerun changed image version.'
    }
    foreach ($mode in @('foreign-group', 'wrong-deployment', 'partial-group', 'extra-resource', 'region-change', 'size-change', 'invalid-exists')) {
        Test-Case "Existing RG rejects $mode" {
            $global:PocAzdTestState.Mode = $mode
            $global:PocAzdTestState.Exists = $true
            $settings = Get-PocAzdConfiguration
            Assert-Throws { Assert-PocAzdResourceGroup $settings } ''
        }
    }
    Test-Case 'VM Agent readiness polls reads only and eventually succeeds' {
        $global:PocAzdTestState.Mode = 'agent-delayed'
        $settings = Get-PocAzdConfiguration
        $target = @{ SubscriptionId = $settings.AZURE_SUBSCRIPTION_ID; ResourceGroupName = $settings.ResourceGroupName; VmName = $settings.VmName }
        Wait-PocAzdVmAgent $target -MaxAttempts 2 -DelaySeconds 0
        Assert-True ($global:PocAzdTestState.AgentReads -eq 2 -and $global:PocAzdTestState.Runs -eq 0) 'Unexpected polling or guest command.'
    }
    Test-Case 'Readiness timeout submits no guest command' {
        $global:PocAzdTestState.Mode = 'agent-not-ready'
        $settings = Get-PocAzdConfiguration
        $target = @{ SubscriptionId = $settings.AZURE_SUBSCRIPTION_ID; ResourceGroupName = $settings.ResourceGroupName; VmName = $settings.VmName }
        Assert-Throws { Wait-PocAzdVmAgent $target -MaxAttempts 2 -DelaySeconds 0 } 'timed out'
        Assert-True ($global:PocAzdTestState.Runs -eq 0) 'Guest command ran before readiness.'
    }
    Test-Case 'Postprovision initializes once, tests both cases and hands off at step 5' {
        $global:PocAzdTestState.Exists = $true
        $global:PocAzdTestState.Answers.Clear()
        $global:PocAzdTestState.Answers.Enqueue('INITIALIZE')
        $messages = (& $post 6>&1 | Out-String)
        Assert-True ($global:PocAzdTestState.Runs -eq 3) 'Expected one initialization and two reads.'
        Assert-True ($messages.Contains('[6/6] Lab preparation complete') -and $messages -like '*step 5*') 'Missing completion/handoff.'
        Assert-True (@($global:PocAzdTestState.Calls | Where-Object { $_ -like '*role assignment*' }).Count -eq 0) 'Agent access was granted.'
    }
    Test-Case 'Guest execution failure is never retried' {
        $global:PocAzdTestState.Exists = $true
        $global:PocAzdTestState.Mode = 'guest-failure'
        $global:PocAzdTestState.Answers.Clear()
        $global:PocAzdTestState.Answers.Enqueue('INITIALIZE')
        Assert-Throws { & $post } 'No automatic retry'
        Assert-True ($global:PocAzdTestState.Runs -eq 1) 'Guest failure was retried.'
    }
    Test-Case 'Preview alone cannot initialize a previously deployed guest' {
        $global:PocAzdTestState.Exists = $true
        $global:PocAzdTestState.Mode = 'preview-only'
        Assert-Throws { & $post } 'Preview alone'
        Assert-True ($global:PocAzdTestState.Runs -eq 0) 'Preview submitted a guest command.'
    }
    foreach ($mode in @('wrong-count', 'wrong-source', 'partial-result')) {
        Test-Case "Postprovision rejects $mode" {
            $global:PocAzdTestState.Exists = $true
            $global:PocAzdTestState.Mode = $mode
            $global:PocAzdTestState.Answers.Clear()
            $global:PocAzdTestState.Answers.Enqueue('INITIALIZE')
            Assert-Throws { & $post } ''
        }
    }
    Write-Host "$script:passed azd workflow checks passed (mocked; no Azure operations)."
} finally {
    Remove-Variable PocAzdTestState -Scope Global -ErrorAction SilentlyContinue
    $env:AZURE_ENV_NAME = $originalEnvironmentName
}
