#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tenant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$subscription = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
$script:passed = 0
$global:LabWorkflowTestState = @{ Mode = 'success'; Calls = $null; Tenant = $tenant; Subscription = $subscription }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $failed = $false
    try { $null = & $Action } catch { $failed = $true }
    Assert-True $failed $Message
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    $script:calls = [Collections.Generic.List[string]]::new()
    $global:LabWorkflowTestState.Calls = $script:calls
    $global:LabWorkflowTestState.Mode = 'success'
    try { & $Action }
    catch { throw "Test '$Name' failed: $($_.Exception.Message)" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function az {
    $arguments = @($args)
    $state = $global:LabWorkflowTestState
    $state.Calls.Add(($arguments -join ' '))
    $global:LASTEXITCODE = 0
    if ($state.Mode -eq 'cli-failure') {
        $global:LASTEXITCODE = 1
        return
    }
    if ($arguments[0] -eq 'login') { return }
    if ($arguments[0] -eq 'account') {
        $account = @{
            id = $state.Subscription; tenantId = $state.Tenant; state = 'Enabled'
            environmentName = 'AzureCloud'; user = @{ name = '<OPERATOR>' }
        }
        switch ($state.Mode) {
            'wrong-tenant' { $account.tenantId = 'cccccccc-cccc-cccc-cccc-cccccccccccc' }
            'wrong-subscription' { $account.id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' }
            'disabled' { $account.state = 'Disabled' }
            'wrong-cloud' { $account.environmentName = 'AzureUSGovernment' }
        }
        return ($account | ConvertTo-Json)
    }
    if ($arguments[0] -eq 'group' -and $arguments[1] -eq 'exists') {
        if ($state.Mode -eq 'exists') { return 'true' }
        if ($state.Mode -eq 'invalid-exists') { return '"false"' }
        return 'false'
    }
    if ($arguments[0] -eq 'group' -and $arguments[1] -eq 'create') {
        $provisioningState = if ($state.Mode -eq 'partial') { 'Failed' } else { 'Succeeded' }
        return (@{
            name = 'rg-sp-sre-poc1'; properties = @{ provisioningState = $provisioningState }
            tags = @{ purpose = 'SP-SRE-POC1'; environment = 'nonproduction' }
        } | ConvertTo-Json)
    }
    if ($arguments[0] -eq 'provider') { return '{"registrationState":"Registered"}' }
    if ($arguments[0] -eq 'vm' -and $arguments[1] -eq 'list-skus') {
        return (ConvertTo-Json -Depth 6 -InputObject @(@{
            name = 'Standard_D2s_v6'; resourceType = 'virtualMachines'; family = 'StandardDsv6Family'
            restrictions = @()
            capabilities = @(
                @{ name = 'vCPUs'; value = '2' }
                @{ name = 'HyperVGenerations'; value = 'V2' }
            )
        }))
    }
    if ($arguments[0] -eq 'vm' -and $arguments[1] -eq 'list-usage') {
        return (ConvertTo-Json -Depth 4 -InputObject @(
            @{ name = @{ value = 'cores' }; currentValue = 0; limit = 100 }
            @{ name = @{ value = 'StandardDsv6Family' }; currentValue = 0; limit = 100 }
        ))
    }
    if ($arguments[0] -eq 'vm' -and $arguments[1] -eq 'image') {
        return '{"name":"20348.5773.261025","hyperVGeneration":"V2"}'
    }
    throw "Unexpected mocked CLI command: $($arguments -join ' ')"
}

$contextScript = "$root\scripts\Initialize-LabContext.ps1"
$groupScript = "$root\scripts\New-LabResourceGroup.ps1"
$preflightScript = "$root\scripts\Test-Preflight.ps1"
$deployScript = "$root\scripts\Deploy-Lab.ps1"
$contextParameters = @{ TenantId = $tenant; SubscriptionId = $subscription }
$groupParameters = @{ SubscriptionId = $subscription; ResourceGroupName = 'rg-sp-sre-poc1' }

try {
Test-Case 'Workflow scripts parse' {
    foreach ($path in @($contextScript, $groupScript, $preflightScript, $deployScript)) {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "Syntax error in $path"
    }
}
Test-Case 'Context returns only the three shared target parameters without signing in' {
    $target = & $contextScript @contextParameters
    Assert-True ($target -is [hashtable] -and $target.Count -eq 3) 'Expected a splattable three-key target.'
    Assert-True ($target.SubscriptionId -eq $subscription -and
        $target.ResourceGroupName -eq 'rg-sp-sre-poc1' -and $target.VmName -eq 'sp-sre-poc1') 'Wrong target.'
    Assert-True ($script:calls.Count -eq 1 -and $script:calls[0] -like 'account show *') 'Unexpected authentication mutation.'
}
Test-Case 'Sign-in occurs only when explicitly requested and before verification' {
    $null = & $contextScript @contextParameters -SignIn
    Assert-True ($script:calls.Count -eq 2 -and $script:calls[0] -like 'login --tenant *' -and
        $script:calls[1] -like 'account show *') 'Expected explicit login followed by verification.'
}
foreach ($failure in @('wrong-tenant', 'wrong-subscription', 'disabled', 'wrong-cloud', 'cli-failure')) {
    Test-Case "Context rejects $failure" {
        $global:LabWorkflowTestState.Mode = $failure
        Assert-Throws { & $contextScript @contextParameters } 'Invalid account context was accepted.'
    }
}
Test-Case 'Failed sign-in stops before account verification' {
    $global:LabWorkflowTestState.Mode = 'cli-failure'
    Assert-Throws { & $contextScript @contextParameters -SignIn } 'Failed login was accepted.'
    Assert-True ($script:calls.Count -eq 1) 'Verification ran after failed sign-in.'
}
Test-Case 'Empty GUID fails before any Azure call' {
    Assert-Throws { & $contextScript -TenantId ([guid]::Empty) -SubscriptionId $subscription } 'Empty tenant accepted.'
    Assert-Throws { & $contextScript -TenantId $tenant -SubscriptionId ([guid]::Empty) } 'Empty subscription accepted.'
    Assert-True ($script:calls.Count -eq 0) 'Azure was called with an empty GUID.'
}
Test-Case 'WhatIf never creates a resource group or returns a success result' {
    $result = & $groupScript @groupParameters -WhatIf
    Assert-True ($null -eq $result -and $script:calls.Count -eq 1) 'WhatIf created resources or emitted success.'
}
Test-Case 'Confirmed group creation uses explicit subscription and both lab tags' {
    $group = & $groupScript @groupParameters -Confirm:$false
    Assert-True ($group.properties.provisioningState -eq 'Succeeded') 'Expected a verified group result.'
    Assert-True ($script:calls.Count -eq 2 -and $script:calls[1] -like "*--subscription $subscription*" -and
        $script:calls[1] -like '*purpose=SP-SRE-POC1 environment=nonproduction*') 'Missing scope or safety tags.'
}
foreach ($failure in @('exists', 'invalid-exists', 'cli-failure', 'partial')) {
    Test-Case "Resource group rejects $failure" {
        $global:LabWorkflowTestState.Mode = $failure
        Assert-Throws { & $groupScript @groupParameters -Confirm:$false } 'Unsafe or failed group creation was accepted.'
        if ($failure -ne 'partial') {
            Assert-True ($script:calls.Count -eq 1) 'Create ran despite an unverified absence.'
        }
    }
}
foreach ($path in @($preflightScript, $deployScript)) {
    foreach ($parameterName in @('Location', 'VmSize')) {
        Test-Case "$(Split-Path $path -Leaf) rejects blank $parameterName before Azure calls" {
            foreach ($value in @($null, '', '   ')) {
                $parameters = @{ SubscriptionId = $subscription; Location = 'eastus2'; VmSize = 'Standard_D2s_v6' }
                if ($path -eq $deployScript) { $parameters.ResourceGroupName = 'rg-sp-sre-poc1' }
                $parameters[$parameterName] = $value
                $failure = $null
                try { $null = & $path @parameters }
                catch { $failure = $_ }
                Assert-True ($null -ne $failure) "Blank $parameterName was accepted."
                Assert-True ($failure.Exception.Message -like "*'$parameterName'*") 'Error must name the missing input, not the internal Arguments parameter.'
                Assert-True ($script:calls.Count -eq 0) 'Azure was called before invalid input was rejected.'
            }
        }
    }
}
Test-Case 'Explicit region and size preserve the preflight output contract' {
    $result = & $preflightScript -SubscriptionId $subscription -Location 'eastus2' -VmSize 'Standard_D2s_v6'
    Assert-True ($result.subscriptionId -eq $subscription -and $result.location -eq 'eastus2' -and
        $result.vmSize -eq 'Standard_D2s_v6' -and $result.imageVersion -eq '20348.5773.261025') 'Preflight result contract changed.'
    $skuCalls = @($script:calls | Where-Object { $_ -like 'vm list-skus *' })
    Assert-True ($skuCalls.Count -eq 1 -and $skuCalls[0] -like '*--location eastus2 --size Standard_D2s_v6*') 'Selected region and size were not forwarded.'
}
[pscustomobject]@{ passed = $script:passed; scope = 'Mocked workflow checks only; no Azure calls.' }
}
finally {
    Remove-Variable -Name LabWorkflowTestState -Scope Global
}
