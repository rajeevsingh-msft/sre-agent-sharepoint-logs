#requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipWindowsPowerShellCompatibility)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\scripts\Common.ps1"
$temp = Join-Path ([IO.Path]::GetTempPath()) ("sp-sre-poc1-tests-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temp
$lab = Join-Path $temp 'fixture'
$script:results = @()
$script:aclRecords = @()
$global:SmokeContractTestState = @{ Mode = 'valid'; Runs = 0 }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action)
    $failed = $false
    try { $null = & $Action } catch { $failed = $true }
    Assert-True $failed 'Expected an explicit error.'
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    try { & $Action }
    catch { throw "Test '$Name' failed: $($_.Exception.Message)" }
    $script:results += [pscustomobject]@{ test = $Name; status = 'PASS' }
}
function Set-Acl {
    param([string]$LiteralPath, $AclObject)
    $script:aclRecords += [pscustomobject]@{ Path = $LiteralPath; Acl = $AclObject }
}
function New-GuestBlock {
    param([string]$Name)
    $text = [IO.File]::ReadAllText("$root\scripts\$Name")
    $original = "`$folder = 'C:\SP-SRE-Lab'"
    Assert-True ($text.Contains($original)) 'Guest script must have the reviewed fixed source assignment.'
    return [scriptblock]::Create($text.Replace($original, "`$folder = '$($lab.Replace("'", "''"))'"))
}
function New-CommandResult {
    param([string]$Stdout = '{"kind":"test"}', [string]$Stderr = '', [string]$Code = 'succeeded')
    return [pscustomobject]@{ value = @(
        [pscustomobject]@{ code = "ComponentStatus/StdOut/$Code"; message = $Stdout },
        [pscustomobject]@{ code = 'ComponentStatus/StdErr/succeeded'; message = $Stderr }
    ) }
}
function az {
    $arguments = @($args)
    $state = $global:SmokeContractTestState
    $global:LASTEXITCODE = 0
    if (($arguments[0..1] -join ' ') -eq 'vm show') {
        return '{"tags":{"purpose":"SP-SRE-POC1","environment":"nonproduction"},"storageProfile":{"osDisk":{"osType":"Windows"}}}'
    }
    if (($arguments[0..1] -join ' ') -eq 'vm get-instance-view') {
        $power = if ($state.Mode -eq 'vm-stopped') { 'PowerState/deallocated' } else { 'PowerState/running' }
        $provisioning = if ($state.Mode -eq 'vm-failed') { 'ProvisioningState/failed' } else { 'ProvisioningState/succeeded' }
        $agent = if ($state.Mode -eq 'agent-not-ready') { 'ProvisioningState/failed' } else { 'ProvisioningState/succeeded' }
        return (@{ instanceView = @{ statuses = @(@{ code = $power }, @{ code = $provisioning })
            vmAgent = @{ statuses = @(@{ code = $agent }) } } } | ConvertTo-Json -Depth 6)
    }
    if (($arguments[0..2] -join ' ') -eq 'vm extension list') {
        if ($state.Mode -eq 'extension-failed') { return '[{"provisioningState":"Failed"}]' }
        return '[]'
    }
    if (($arguments[0..2] -join ' ') -eq 'vm run-command invoke') {
        $state.Runs++
        if ($state.Mode -eq 'initialize') {
            $body = @{ kind = 'uls-lab-initialized'; synthetic = $true
                readerSha256 = (Get-FileHash "$root\scripts\Read-UlsLab.ps1").Hash }
        } else {
            $body = @{
                kind = 'uls-lab-evidence'; synthetic = $true; source = 'sp-sre-poc1'
                file = 'C:\SP-SRE-Lab\Synthetic-ULS.log'
                correlationId = '11111111-1111-1111-1111-111111111111'
                queryUtc = [DateTime]::UtcNow.ToString('o')
                linesRead = 4; matchingRecordsReturned = 2; partial = $false
                coverage = 'One synthetic file; mocked complete scan.'
                evidence = @(@{ lineNumber = 2; fragment = 'Synthetic first record' },
                    @{ lineNumber = 3; fragment = 'Synthetic second record' })
            }
            switch ($state.Mode) {
                'zero' { $body.matchingRecordsReturned = 0; $body.evidence = @() }
                'limits' {
                    $body.linesRead = 10000; $body.matchingRecordsReturned = 3; $body.partial = $true
                    $body.evidence += @{ lineNumber = 10000; fragment = 'x' * 180 }
                }
                'uppercase-source' { $body.source = 'SP-SRE-POC1' }
                'wrong-kind' { $body.kind = 'other' }
                'wrong-source' { $body.source = 'other-vm' }
                'wrong-file' { $body.file = 'C:\other.log' }
                'wrong-guid' { $body.correlationId = '33333333-3333-3333-3333-333333333333' }
                'synthetic-string' { $body.synthetic = 'true' }
                'partial-string' { $body.partial = 'false' }
                'count-string' { $body.matchingRecordsReturned = '2' }
                'count-fraction' { $body.matchingRecordsReturned = 1.5 }
                'lines-string' { $body.linesRead = '4' }
                'negative-lines' { $body.linesRead = -1 }
                'scan-limit' { $body.linesRead = 10001 }
                'match-limit' { $body.matchingRecordsReturned = 4 }
                'count-mismatch' { $body.matchingRecordsReturned = 1 }
                'empty-coverage' { $body.coverage = '' }
                'missing-time' { $body.Remove('queryUtc') }
                'invalid-time' { $body.queryUtc = 'invalidZ' }
                'nonutc-time' { $body.queryUtc = '2026-10-29T12:00:00+01:00' }
                'duplicate-line' { $body.evidence[1].lineNumber = 2 }
                'zero-line' { $body.evidence[0].lineNumber = 0 }
                'past-line' { $body.evidence[0].lineNumber = 5 }
                'string-line' { $body.evidence[0].lineNumber = '2' }
                'long-fragment' { $body.evidence[0].fragment = 'x' * 181 }
                'nonstring-fragment' { $body.evidence[0].fragment = 42 }
                'nonarray-evidence' { $body.matchingRecordsReturned = 1; $body.evidence = $body.evidence[0] }
            }
        }
        return (New-CommandResult -Stdout ($body | ConvertTo-Json -Depth 6 -Compress) | ConvertTo-Json -Depth 8)
    }
    throw "Unexpected mocked Azure CLI command: $($arguments -join ' ')"
}
try {
    Test-Case 'All scripts parse' {
        foreach ($file in Get-ChildItem "$root\scripts" -Filter '*.ps1') {
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            Assert-True ($errors.Count -eq 0) "Syntax error in $($file.Name)"
        }
    }
    $initialize = New-GuestBlock 'Initialize-UlsLab.ps1'
    $reader = New-GuestBlock 'Read-UlsLab.ps1'
    $readerBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$root\scripts\Read-UlsLab.ps1"))
    Test-Case 'Initialize creates exact fixture and reader' {
        $result = & $initialize -ReaderBase64 $readerBase64 | ConvertFrom-Json
        Assert-True ($result.kind -eq 'uls-lab-initialized') 'Missing initialization envelope.'
        Assert-True ($result.readerSha256 -eq (Get-FileHash "$root\scripts\Read-UlsLab.ps1").Hash) 'Reader hash mismatch.'
        Assert-True ((Get-Item "$lab\Synthetic-ULS.log").Length -lt 1KB) 'Unexpected fixture size.'
    }
    Test-Case 'ACL intent allows only SYSTEM and Administrators' {
        $directoryAcl = $script:aclRecords[0].Acl
        Assert-True $directoryAcl.AreAccessRulesProtected 'Directory inheritance must be disabled.'
        $sids = @($directoryAcl.Access | ForEach-Object {
            $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        })
        Assert-True ($sids.Count -eq 2 -and $sids -contains 'S-1-5-18' -and
            $sids -contains 'S-1-5-32-544') 'Unexpected directory access rules.'
    }
    Test-Case 'Identical initialization is idempotent' {
        $before = (Get-Item "$lab\Synthetic-ULS.log").LastWriteTimeUtc
        $null = & $initialize -ReaderBase64 $readerBase64
        Assert-True ((Get-Item "$lab\Synthetic-ULS.log").LastWriteTimeUtc -eq $before) 'Existing fixture was rewritten.'
    }
    $fixture = [IO.File]::ReadAllBytes("$lab\Synthetic-ULS.log")
    Test-Case 'Known GUID returns exactly two complete records' {
        $json = & $reader -CorrelationId '11111111-1111-1111-1111-111111111111'
        $result = $json | ConvertFrom-Json
        Assert-True ($result.matchingRecordsReturned -eq 2 -and $result.evidence.Count -eq 2) 'Expected two matches.'
        Assert-True ($result.partial -eq $false -and $result.synthetic -eq $true) 'Fixture must be complete and synthetic.'
        Assert-True ($result.linesRead -eq 4 -and $result.file -eq "$lab\Synthetic-ULS.log") 'Unexpected source coverage.'
        Assert-True ($json -match '"queryUtc":"[^"]+Z"') 'Expected a UTC query timestamp.'
        Assert-True ([Text.Encoding]::UTF8.GetByteCount($json) -le 2500) 'Output budget exceeded.'
    }
    Test-Case 'Absent GUID is a scoped zero-result success' {
        $result = & $reader -CorrelationId '33333333-3333-3333-3333-333333333333' | ConvertFrom-Json
        Assert-True ($result.matchingRecordsReturned -eq 0 -and $result.evidence.Count -eq 0 -and
            $result.partial -eq $false) 'Unexpected absent-GUID contract.'
    }
    if ($SkipWindowsPowerShellCompatibility) {
        Write-Warning 'Windows PowerShell 5.1 execution was explicitly skipped; guest-runtime acceptance remains unverified.'
        $script:results += [pscustomobject]@{
            test = 'Windows PowerShell 5.1 runs the guest initializer and reader'
            status = 'SKIPPED (explicit request; not validated)'
        }
    }
    else {
      Test-Case 'Windows PowerShell 5.1 runs the guest initializer and reader' {
        $windowsPowerShell = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        Assert-True (Test-Path -LiteralPath $windowsPowerShell) 'Windows PowerShell 5.1 is required for guest compatibility checks.'
        [IO.File]::WriteAllText("$temp\guest-initialize.ps1", $initialize.ToString())
        [IO.File]::WriteAllText("$temp\guest-reader.ps1", $reader.ToString())
        $runner = @"
`$ErrorActionPreference = 'Stop'
function Set-Acl { param(`$LiteralPath, `$AclObject) }
& '$temp\guest-initialize.ps1' -ReaderBase64 '$readerBase64' | Out-Null
& '$temp\guest-reader.ps1' -CorrelationId '11111111-1111-1111-1111-111111111111'
"@
        [IO.File]::WriteAllText("$temp\guest-runner.ps1", $runner)
        $json = & $windowsPowerShell -NoProfile -NonInteractive -File "$temp\guest-runner.ps1"
        Assert-True ($LASTEXITCODE -eq 0) 'Guest scripts failed in Windows PowerShell 5.1.'
        $result = $json -join "`n" | ConvertFrom-Json
        Assert-True ($result.matchingRecordsReturned -eq 2 -and $result.partial -eq $false) 'Unexpected Windows PowerShell guest result.'
      }
    }
    Test-Case 'Invalid GUID fails before reading' { Assert-Throws { & $reader -CorrelationId 'not-a-guid' } }
    Test-Case 'Changed fixture is never overwritten' {
        [IO.File]::AppendAllText("$lab\Synthetic-ULS.log", 'changed')
        Assert-Throws { & $initialize -ReaderBase64 $readerBase64 }
        [IO.File]::WriteAllBytes("$lab\Synthetic-ULS.log", $fixture)
    }
    Test-Case 'Changed installed reader is never overwritten' {
        [IO.File]::AppendAllText("$lab\Read-UlsLab.ps1", '#changed')
        Assert-Throws { & $initialize -ReaderBase64 $readerBase64 }
        [IO.File]::WriteAllBytes("$lab\Read-UlsLab.ps1", [Convert]::FromBase64String($readerBase64))
    }
    Test-Case 'Missing file is an error, not zero matches' {
        Move-Item "$lab\Synthetic-ULS.log" "$lab\fixture.backup"
        Assert-Throws { & $reader -CorrelationId ([guid]::Empty) }
        Move-Item "$lab\fixture.backup" "$lab\Synthetic-ULS.log"
    }
    Test-Case 'Oversized file is rejected' {
        [IO.File]::WriteAllBytes("$lab\Synthetic-ULS.log", [byte[]]::new(1MB + 1))
        Assert-Throws { & $reader -CorrelationId ([guid]::Empty) }
    }
    Test-Case 'Line budget reports partial coverage' {
        [IO.File]::WriteAllText("$lab\Synthetic-ULS.log", ("unrelated`n" * 10001))
        $result = & $reader -CorrelationId ([guid]::Empty) | ConvertFrom-Json
        Assert-True ($result.linesRead -eq 10000 -and $result.partial -eq $true) 'Line budget must be explicit.'
    }
    Test-Case 'Match budget reports partial coverage' {
        [IO.File]::WriteAllText("$lab\Synthetic-ULS.log", ("11111111-1111-1111-1111-111111111111`n" * 4))
        $result = & $reader -CorrelationId '11111111-1111-1111-1111-111111111111' | ConvertFrom-Json
        Assert-True ($result.matchingRecordsReturned -eq 3 -and $result.partial -eq $true) 'Match cap must be explicit.'
    }
    Test-Case 'Fragment budget is enforced' {
        [IO.File]::WriteAllText("$lab\Synthetic-ULS.log", ('11111111-1111-1111-1111-111111111111' + ('x' * 500)))
        $result = & $reader -CorrelationId '11111111-1111-1111-1111-111111111111' | ConvertFrom-Json
        Assert-True ($result.evidence[0].fragment.Length -eq 180) 'Expected 180-character fragment limit.'
    }
    Test-Case 'Malformed UTF8 is an explicit error' {
        [IO.File]::WriteAllBytes("$lab\Synthetic-ULS.log", [byte[]]@(0xC3, 0x28))
        Assert-Throws { & $reader -CorrelationId ([guid]::Empty) }
    }
    Test-Case 'Locked source is an explicit error' {
        [IO.File]::WriteAllBytes("$lab\Synthetic-ULS.log", $fixture)
        $handle = [IO.File]::Open("$lab\Synthetic-ULS.log", 'Open', 'ReadWrite', 'None')
        try { Assert-Throws { & $reader -CorrelationId ([guid]::Empty) } }
        finally { $handle.Dispose() }
    }
    Test-Case 'Directory reparse point is rejected by reader and initializer' {
        Move-Item -LiteralPath $lab -Destination "$temp\original"
        $null = New-Item -ItemType Junction -Path $lab -Target "$temp\original"
        try {
            Assert-Throws { & $reader -CorrelationId ([guid]::Empty) }
            Assert-Throws { & $initialize -ReaderBase64 $readerBase64 }
        }
        finally {
            [IO.Directory]::Delete($lab)
            Move-Item -LiteralPath "$temp\original" -Destination $lab
        }
    }
    Test-Case 'Valid Run Command JSON is accepted' {
        $result = ConvertFrom-LabCommandResult (New-CommandResult)
        Assert-True ($result.kind -eq 'test') 'Valid JSON was not parsed.'
    }
    Test-Case 'Guest stderr cannot masquerade as success' {
        Assert-Throws { ConvertFrom-LabCommandResult (New-CommandResult -Stderr 'guest failure') }
    }
    Test-Case 'Failed status cannot masquerade as success' {
        Assert-Throws { ConvertFrom-LabCommandResult (New-CommandResult -Code 'failed') }
    }
    Test-Case 'Truncated or non-JSON output is rejected' {
        Assert-Throws { ConvertFrom-LabCommandResult (New-CommandResult -Stdout '{"truncated":') }
        Assert-Throws { ConvertFrom-LabCommandResult (New-CommandResult -Stdout 'not JSON') }
    }
    Test-Case 'Empty and oversized transport results are rejected' {
        Assert-Throws { ConvertFrom-LabCommandResult ([pscustomobject]@{ value = @() }) }
        Assert-Throws { ConvertFrom-LabCommandResult (New-CommandResult -Stdout ('x' * 3001)) }
    }
    Test-Case 'Generated agent prompt pins target and reader hash' {
        $prompt = & "$root\scripts\New-AgentPrompt.ps1" -SubscriptionId '00000000-0000-0000-0000-000000000001' -ResourceGroupName 'rg-test'
        Assert-True ($prompt.Contains((Get-FileHash "$root\scripts\Read-UlsLab.ps1").Hash)) 'Missing reader hash.'
        Assert-True ($prompt.Contains('/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/sp-sre-poc1')) 'Missing fixed target.'
    }
    $target = @{ SubscriptionId = '00000000-0000-0000-0000-000000000001'
        ResourceGroupName = 'rg-test'; VmName = 'sp-sre-poc1' }
    $positive = '11111111-1111-1111-1111-111111111111'
    foreach ($mode in @('valid', 'uppercase-source', 'zero', 'limits')) {
        Test-Case "Smoke wrapper accepts $mode evidence" {
            $global:SmokeContractTestState.Mode = $mode
            $result = & "$root\scripts\Get-LabEvidence.ps1" @target -CorrelationId $positive
            $expected = if ($mode -eq 'zero') { 0 } elseif ($mode -eq 'limits') { 3 } else { 2 }
            Assert-True ($result.matchingRecordsReturned -eq $expected) 'Unexpected evidence count.'
            Assert-True ($result.queryUtc -is [string] -and $result.queryUtc.EndsWith('Z')) 'UTC normalization failed.'
        }
    }
    foreach ($mode in @('wrong-kind', 'wrong-source', 'wrong-file', 'wrong-guid', 'synthetic-string',
        'partial-string', 'count-string', 'count-fraction', 'lines-string', 'negative-lines',
        'scan-limit', 'match-limit', 'count-mismatch', 'empty-coverage', 'missing-time',
        'invalid-time', 'nonutc-time', 'duplicate-line', 'zero-line', 'past-line', 'string-line',
        'long-fragment', 'nonstring-fragment', 'nonarray-evidence')) {
        Test-Case "Smoke wrapper rejects $mode evidence" {
            $global:SmokeContractTestState.Mode = $mode
            Assert-Throws { & "$root\scripts\Get-LabEvidence.ps1" @target -CorrelationId $positive }
        }
    }
    Test-Case 'Ready smoke initialization preserves the reviewed reader contract' {
        $global:SmokeContractTestState.Mode = 'initialize'
        $result = & "$root\scripts\Initialize-Lab.ps1" @target -Confirm:$false
        Assert-True ($result.readerSha256 -eq (Get-FileHash "$root\scripts\Read-UlsLab.ps1").Hash) 'Reader changed.'
    }
    foreach ($mode in @('vm-stopped', 'vm-failed', 'agent-not-ready', 'extension-failed')) {
        Test-Case "Smoke operations reject $mode before guest execution" {
            $global:SmokeContractTestState.Mode = $mode
            $global:SmokeContractTestState.Runs = 0
            Assert-Throws { & "$root\scripts\Initialize-Lab.ps1" @target -Confirm:$false }
            Assert-Throws { & "$root\scripts\Get-LabEvidence.ps1" @target -CorrelationId $positive }
            Assert-True ($global:SmokeContractTestState.Runs -eq 0) 'Unready VM received a guest command.'
        }
    }
    $script:results
    $passed = @($script:results | Where-Object status -EQ 'PASS').Count
    $skipped = $script:results.Count - $passed
    Write-Host "$passed local checks passed; $skipped skipped. ACL application is mocked; no Azure calls were made."
}
finally {
    Remove-Variable -Name SmokeContractTestState -Scope Global
    foreach ($name in @('Synthetic-ULS.log', 'Read-UlsLab.ps1', 'fixture.backup')) {
        $path = Join-Path $lab $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
    if (Test-Path -LiteralPath $lab -PathType Container) { Remove-Item -LiteralPath $lab }
    foreach ($name in @('guest-initialize.ps1', 'guest-reader.ps1', 'guest-runner.ps1')) {
        $path = Join-Path $temp $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    Remove-Item -LiteralPath $temp
}
