#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\scripts\Common.ps1"
if (Get-Variable LabCommandTransportTestState -Scope Global -ErrorAction SilentlyContinue) {
    throw 'Transport test state already exists. Run this suite in a separate PowerShell process.'
}
$script:passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Expected)
    $failure = $null
    try { $null = & $Action } catch { $failure = $_ }
    Assert-True ($null -ne $failure) 'Expected an explicit error.'
    Assert-True ($failure.Exception.Message -like "*$Expected*") "Unexpected error: $failure"
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    $global:LabCommandTransportTestState = @{
        Mode = 'success'; Calls = 0; Path = $null; Payload = $null; Arguments = @()
    }
    try { & $Action }
    catch { throw "Test '$Name' failed: $($_.Exception.Message)" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function az {
    $state = $global:LabCommandTransportTestState
    $state.Calls++
    $state.Arguments = @($args)
    $index = [array]::IndexOf($state.Arguments, '--scripts')
    Assert-True ($index -ge 0) 'Missing script argument.'
    $reference = $state.Arguments[$index + 1]
    Assert-True ($reference.StartsWith('@')) 'Inline guest code reached the CLI boundary.'
    Assert-True ($reference -notmatch '[\r\n]') 'A multiline argument reached az.cmd.'
    $state.Path = $reference.Substring(1)
    Assert-True (Test-Path -LiteralPath $state.Path -PathType Leaf) 'Payload file was not available during the invocation.'
    $state.Payload = [IO.File]::ReadAllText($state.Path)
    $state.Bytes = [IO.File]::ReadAllBytes($state.Path)
    $global:LASTEXITCODE = 0
    if ($state.Mode -eq 'cli-failure') { $global:LASTEXITCODE = 1; return }
    $stdout = '{"kind":"transport-test"}'
    $stderr = ''
    $code = 'ComponentStatus/StdOut/succeeded'
    switch ($state.Mode) {
        'invalid-json' { $stdout = '{"truncated":' }
        'empty-stdout' { $stdout = '' }
        'missing-stdout' { $code = 'ProvisioningState/succeeded' }
        'stderr' { $stderr = 'synthetic guest error' }
        'failed-status' { $code = 'ComponentStatus/StdOut/failed' }
        'oversized' { $stdout = 'x' * 3001 }
    }
    $entries = @(
        @{ code = $code; message = $stdout },
        @{ code = 'ComponentStatus/StdErr/succeeded'; message = $stderr }
    )
    if ($state.Mode -eq 'duplicate-stdout') { $entries += @{ code = $code; message = $stdout } }
    return (@{ value = $entries } | ConvertTo-Json -Depth 4 -Compress)
}
$target = @{
    SubscriptionId = '00000000-0000-0000-0000-000000000001'
    ResourceGroupName = 'rg-transport-test'
    VmName = 'sp-sre-poc1'
}

try {
    Test-Case 'Multiline guest code reaches the CLI through an exact UTF-8 file' {
        $payload = "`$ErrorActionPreference = 'Stop'`r`n& 'C:\SP-SRE-Lab\Read-UlsLab.ps1' -CorrelationId '11111111-1111-1111-1111-111111111111'`r`n# UTF-8 probe: $([char]0xE9)"
        $result = Invoke-LabCommand @target -Script $payload
        $state = $global:LabCommandTransportTestState
        Assert-True ($result.kind -eq 'transport-test') 'Result contract was not parsed.'
        Assert-True ($state.Payload -ceq $payload) 'Payload lines, quotes or encoding changed.'
        Assert-True ($state.Bytes.Length -eq [Text.Encoding]::UTF8.GetByteCount($payload)) 'Payload is not BOM-free UTF-8.'
        Assert-True (-not (Test-Path -LiteralPath $state.Path)) 'Temporary script was not removed.'
        Assert-True ($state.Calls -eq 1) 'More than one guest invocation was submitted.'
        Assert-True (($state.Arguments -join ' ') -like "*--subscription $($target.SubscriptionId)*") 'Explicit subscription was lost.'
    }
    Test-Case 'Single-line code also uses a file reference' {
        $null = Invoke-LabCommand @target -Script 'Write-Output ''{"kind":"test"}'''
        $state = $global:LabCommandTransportTestState
        Assert-True ($state.Payload -eq 'Write-Output ''{"kind":"test"}''') 'Single-line payload changed.'
        Assert-True (-not (Test-Path -LiteralPath $state.Path)) 'Temporary script remained.'
    }
    Test-Case 'Existing source file references and script parameters remain unchanged' {
        $source = "$root\scripts\Initialize-UlsLab.ps1"
        $hash = (Get-FileHash -LiteralPath $source).Hash
        $null = Invoke-LabCommand @target -Script "@$source" -ScriptParameters @('ReaderBase64=c3ludGhldGlj')
        $state = $global:LabCommandTransportTestState
        Assert-True ($state.Path -eq $source -and (Test-Path -LiteralPath $source)) 'Caller source file was replaced or deleted.'
        Assert-True ((Get-FileHash -LiteralPath $source).Hash -eq $hash) 'Caller source was modified.'
        $index = [array]::IndexOf($state.Arguments, '--parameters')
        Assert-True ($index -ge 0 -and $state.Arguments[$index + 1] -eq 'ReaderBase64=c3ludGhldGlj') 'Script parameters changed.'
    }
    foreach ($case in @(
        @{ Mode = 'cli-failure'; Error = 'No automatic retry' },
        @{ Mode = 'invalid-json'; Error = 'JSON' },
        @{ Mode = 'empty-stdout'; Error = 'one nonempty guest stdout' },
        @{ Mode = 'missing-stdout'; Error = 'Found 0 stdout entries' },
        @{ Mode = 'duplicate-stdout'; Error = 'Found 2 stdout entries' },
        @{ Mode = 'stderr'; Error = 'reported stderr' },
        @{ Mode = 'failed-status'; Error = 'not successful' },
        @{ Mode = 'oversized'; Error = 'transport safety budget' }
    )) {
        Test-Case "Reject $($case.Mode), delete the temporary file and never retry" {
            $global:LabCommandTransportTestState.Mode = $case.Mode
            Assert-Throws { Invoke-LabCommand @target -Script "Write-Output 'first'`nWrite-Output 'second'" } $case.Error
            $state = $global:LabCommandTransportTestState
            Assert-True ($state.Calls -eq 1) 'Failed guest invocation was retried.'
            Assert-True (-not (Test-Path -LiteralPath $state.Path)) 'Temporary payload leaked after failure.'
        }
    }
    Test-Case 'CLI failure never deletes an existing caller-owned script' {
        $source = "$root\scripts\Initialize-UlsLab.ps1"
        $global:LabCommandTransportTestState.Mode = 'cli-failure'
        Assert-Throws { Invoke-LabCommand @target -Script "@$source" } 'No automatic retry'
        Assert-True (Test-Path -LiteralPath $source) 'Caller-owned source was deleted.'
    }
    Write-Host "$script:passed transport checks passed (mocked; no Azure operations)."
}
finally {
    Remove-Variable LabCommandTransportTestState -Scope Global -ErrorAction SilentlyContinue
}
