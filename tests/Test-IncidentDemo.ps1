#requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipWindowsPowerShellCompatibility)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$temp = Join-Path ([IO.Path]::GetTempPath()) ('sp-incident-tests-' + [guid]::NewGuid().ToString('N'))
$lab = Join-Path $temp 'IncidentDemo-v1'
$null = [IO.Directory]::CreateDirectory($temp)
$script:passed = 0
$script:maxOutputBytes = 0
$dataPath = "$root\data\SharePoint-IncidentDemo-v1.tsv"
$readerPath = "$root\scripts\Read-IncidentDemo.ps1"
$fixture = [IO.File]::ReadAllBytes($dataPath)
$readerBytes = [IO.File]::ReadAllBytes($readerPath)
$readerBase64 = [Convert]::ToBase64String($readerBytes)
$memory = [IO.MemoryStream]::new()
$gzip = [IO.Compression.GZipStream]::new($memory, [IO.Compression.CompressionMode]::Compress, $true)
try { $gzip.Write($fixture, 0, $fixture.Length) } finally { $gzip.Dispose() }
$dataBase64 = [Convert]::ToBase64String($memory.ToArray())
$memory.Dispose()
$target = @{ SubscriptionId = '00000000-0000-0000-0000-000000000001'; ResourceGroupName = 'rg-demo-test'; VmName = 'sp-sre-poc1' }
$positive = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
$global:IncidentDemoTestState = @{ Mode = 'success'; Calls = [Collections.Generic.List[string]]::new()
    DataHash = (Get-FileHash $dataPath).Hash; ReaderHash = (Get-FileHash $readerPath).Hash
    Reader = $null; Initializer = $null; StagedPath = $null; AclRecords = @(); Lab = $lab }
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Expected = '')
    $failure = $null
    try { $null = & $Action } catch { $failure = $_ }
    Assert-True ($null -ne $failure) 'Expected an explicit error.'
    if ($Expected) { Assert-True ($failure.Exception.Message -like "*$Expected*") "Unexpected error: $failure" }
}
function Test-Case {
    param([string]$Name, [scriptblock]$Action)
    $global:IncidentDemoTestState.Mode = 'success'
    $global:IncidentDemoTestState.Calls.Clear()
    if (Test-Path "$lab\SharePoint-IncidentDemo-v1.tsv") {
        [IO.File]::WriteAllBytes("$lab\SharePoint-IncidentDemo-v1.tsv", $fixture)
    }
    try { & $Action } catch { throw "Test '$Name' failed: $($_.Exception.Message)" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Set-Acl {
    param([string]$LiteralPath, $AclObject)
    $global:IncidentDemoTestState.AclRecords += [pscustomobject]@{ Path = $LiteralPath; Acl = $AclObject }
}
function Guest-Block {
    param([string]$Name)
    $text = [IO.File]::ReadAllText("$root\scripts\$Name")
    $assignment = "`$folder = 'C:\SP-SRE-Lab\IncidentDemo-v1'"
    Assert-True ($text.Contains($assignment)) 'Guest path must remain fixed.'
    [scriptblock]::Create($text.Replace($assignment, "`$folder = '$($lab.Replace("'", "''"))'"))
}
function az {
    $arguments = @($args)
    $state = $global:IncidentDemoTestState
    $state.Calls.Add(($arguments -join ' '))
    $global:LASTEXITCODE = 0
    if ($state.Mode -eq 'cli-failure') { $global:LASTEXITCODE = 1; return }
    if (($arguments[0..1] -join ' ') -eq 'vm show') {
        return '{"tags":{"purpose":"SP-SRE-POC1","environment":"nonproduction"},"storageProfile":{"osDisk":{"osType":"Windows"}}}'
    }
    if (($arguments[0..1] -join ' ') -eq 'vm get-instance-view') {
        $agent = if ($state.Mode -eq 'agent-not-ready') { 'ProvisioningState/failed' } else { 'ProvisioningState/succeeded' }
        return (@{ instanceView = @{ statuses = @(@{ code = 'PowerState/running' }, @{ code = 'ProvisioningState/succeeded' })
            vmAgent = @{ statuses = @(@{ code = $agent }) } } } | ConvertTo-Json -Depth 6)
    }
    if (($arguments[0..2] -join ' ') -eq 'vm extension list') {
        if ($state.Mode -eq 'extension-pending') { return '[{"provisioningState":"Updating"}]' }
        return '[]'
    }
    if (($arguments[0..2] -join ' ') -eq 'vm run-command invoke') {
        $payload = $arguments[[array]::IndexOf($arguments, '--scripts') + 1]
        if ($payload -like '@*sp-incident-install-*.ps1') {
            $state.StagedPath = $payload.Substring(1)
            $text = [IO.File]::ReadAllText($state.StagedPath)
            $match = [regex]::Match($text, "-DataGzipBase64 '([^']+)' -ReaderBase64 '([^']+)'")
            if (-not $match.Success) { throw 'Mock received an invalid staged installer.' }
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) { throw "Staged installer is not valid PowerShell: $errors" }
            $result = & $state.Initializer -DataGzipBase64 $match.Groups[1].Value `
                -ReaderBase64 $match.Groups[2].Value | ConvertFrom-Json
            $result.file = 'C:\SP-SRE-Lab\IncidentDemo-v1\SharePoint-IncidentDemo-v1.tsv'
            $result.readerPath = 'C:\SP-SRE-Lab\IncidentDemo-v1\Read-IncidentDemo.ps1'
        }
        else {
            if ($payload.StartsWith('@', [StringComparison]::Ordinal)) {
                $payload = [IO.File]::ReadAllText($payload.Substring(1))
            }
            $match = [regex]::Match($payload, "-CorrelationId '([^']+)' -Page (\d+)")
            if (-not $match.Success) { throw 'Mock received an unrecognized reader payload.' }
            $result = & $state.Reader -CorrelationId $match.Groups[1].Value -Page ([int]$match.Groups[2].Value) | ConvertFrom-Json
            $result.source = 'sp-sre-poc1'
            $result.file = 'C:\SP-SRE-Lab\IncidentDemo-v1\SharePoint-IncidentDemo-v1.tsv'
        }
        switch ($state.Mode) {
            'wrong-hash' { $result.datasetSha256 = 'wrong' }
            'wrong-source' { $result.source = 'different-vm' }
            'wrong-page' { $result.page = 1 }
            'wrong-count' { $result.matchingRecordsReturned = 3 }
            'wrong-total' { $result.totalMatchingRecords = -1 }
            'wrong-partial' { $result.partial = $false }
            'wrong-more' { $result.hasMore = $false }
            'wrong-next' { $result.nextPage = 7 }
            'wrong-time' { $result.queryUtc = 'invalid' }
            'wrong-boolean-type' { $result.scanComplete = 'true' }
            'wrong-integer-type' { $result.totalMatchingRecords = '12' }
            'duplicate-lines' { $result.evidence[1].lineNumber = $result.evidence[0].lineNumber }
        }
        $stdout = $result | ConvertTo-Json -Depth 8 -Compress
        $stderr = if ($state.Mode -eq 'stderr') { 'guest error' } else { '' }
        return (@{ value = @(
            @{ code = 'ComponentStatus/StdOut/succeeded'; message = $stdout },
            @{ code = 'ComponentStatus/StdErr/succeeded'; message = $stderr }
        ) } | ConvertTo-Json -Depth 10 -Compress)
    }
    throw "Unexpected mocked CLI command: $($arguments -join ' ')"
}
try {
    Test-Case 'New scripts parse' {
        foreach ($file in Get-ChildItem "$root\scripts" -Filter '*IncidentDemo*.ps1') {
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            Assert-True ($errors.Count -eq 0) "Parse failure: $($file.Name): $errors"
        }
    }
    Test-Case '638 synthetic records include realistic ULS fields and deterministic generation' {
        $rows = @(Import-Csv $dataPath -Delimiter "`t")
        Assert-True ($rows.Count -eq 638) 'Unexpected record count.'
        Assert-True (@($rows | Where-Object Message -NotLike 'SYNTHETIC DEMO: *').Count -eq 0) 'Unlabelled synthetic event.'
        $null = & "$root\scripts\New-IncidentDemoData.ps1" -OutputPath "$temp\regenerated.tsv"
        Assert-True ((Get-FileHash "$temp\regenerated.tsv").Hash -eq (Get-FileHash $dataPath).Hash) 'Generation is not deterministic.'
        Assert-Throws { & "$root\scripts\New-IncidentDemoData.ps1" -OutputPath "$temp\regenerated.tsv" } 'Not overwriting'
    }
    $initialize = Guest-Block 'Initialize-IncidentDemoGuest.ps1'
    $reader = Guest-Block 'Read-IncidentDemo.ps1'
    $global:IncidentDemoTestState.Reader = $reader
    $global:IncidentDemoTestState.Initializer = $initialize
    Test-Case 'Guest setup preserves smoke-test files and creates exact isolated package' {
        [IO.File]::WriteAllText("$temp\Synthetic-ULS.log", 'smoke-test sentinel')
        $result = & $initialize -DataGzipBase64 $dataBase64 -ReaderBase64 $readerBase64 | ConvertFrom-Json
        Assert-True ($result.kind -eq 'uls-incident-demo-initialized') 'Missing initialization envelope.'
        Assert-True ($result.datasetSha256 -eq (Get-FileHash $dataPath).Hash) 'Dataset differs.'
        Assert-True ($result.readerSha256 -eq (Get-FileHash $readerPath).Hash) 'Reader differs.'
        Assert-True ([IO.File]::ReadAllText("$temp\Synthetic-ULS.log") -eq 'smoke-test sentinel') 'Smoke fixture was changed.'
    }
    Test-Case 'ACL intent is restricted to SYSTEM and Administrators' {
        $acl = $global:IncidentDemoTestState.AclRecords[0].Acl
        $sids = @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value })
        Assert-True ($acl.AreAccessRulesProtected -and $sids.Count -eq 2 -and
            $sids -contains 'S-1-5-18' -and $sids -contains 'S-1-5-32-544') 'Unexpected directory ACL.'
    }
    Test-Case 'Identical setup is idempotent and changed files are refused' {
        $before = (Get-Item "$lab\SharePoint-IncidentDemo-v1.tsv").LastWriteTimeUtc
        $null = & $initialize -DataGzipBase64 $dataBase64 -ReaderBase64 $readerBase64
        Assert-True ((Get-Item "$lab\SharePoint-IncidentDemo-v1.tsv").LastWriteTimeUtc -eq $before) 'Identical file was rewritten.'
        [IO.File]::AppendAllText("$lab\SharePoint-IncidentDemo-v1.tsv", 'changed')
        Assert-Throws { & $initialize -DataGzipBase64 $dataBase64 -ReaderBase64 $readerBase64 } 'not overwriting'
    }
    Test-Case 'Changed installed reader is refused' {
        [IO.File]::AppendAllText("$lab\Read-IncidentDemo.ps1", '# changed')
        try { Assert-Throws { & $initialize -DataGzipBase64 $dataBase64 -ReaderBase64 $readerBase64 } 'not overwriting' }
        finally { [IO.File]::WriteAllBytes("$lab\Read-IncidentDemo.ps1", $readerBytes) }
    }
    foreach ($case in @(
        @{ Id = $positive; Count = 12 }, @{ Id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'; Count = 8 },
        @{ Id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3'; Count = 8 },
        @{ Id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4'; Count = 8 },
        @{ Id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'; Count = 0 }
    )) {
        Test-Case "Complete paginated evidence for $($case.Id)" {
            $seen = [Collections.Generic.HashSet[int]]::new()
            $sourceRows = @(Import-Csv $dataPath -Delimiter "`t")
            $page = 0
            do {
                $json = & $reader -CorrelationId $case.Id -Page $page
                $result = $json | ConvertFrom-Json
                $bytes = [Text.Encoding]::UTF8.GetByteCount($json)
                $script:maxOutputBytes = [Math]::Max($script:maxOutputBytes, $bytes)
                Assert-True ($bytes -le 2800) 'Transport budget exceeded.'
                Assert-True ($result.totalMatchingRecords -eq $case.Count -and $result.scanComplete -eq $true) 'Wrong scan contract.'
                Assert-True ($result.partial -eq ($case.Count -gt $result.evidence.Count)) 'Page partial status is misleading.'
                foreach ($record in $result.evidence) {
                    Assert-True ($seen.Add($record.lineNumber)) 'Duplicate page record.'
                    Assert-True ($record.message -ceq $sourceRows[$record.lineNumber - 2].Message) 'Message was truncated or changed.'
                    Assert-True ($sourceRows[$record.lineNumber - 2].Correlation -eq $case.Id) 'Unrelated event leaked into the result.'
                }
                $page++
                Assert-True ($result.nextPage -eq $(if ($result.hasMore) { $page } else { $null })) 'Invalid continuation.'
            } while ($result.hasMore)
            Assert-True ($seen.Count -eq $case.Count) 'Missing incident evidence.'
        }
    }
    Test-Case 'Invalid GUID, negative page and out-of-range continuation fail explicitly' {
        Assert-Throws { & $reader -CorrelationId 'invalid' }
        Assert-Throws { & $reader -CorrelationId $positive -Page -1 }
        Assert-Throws { & $reader -CorrelationId $positive -Page 3 } 'outside'
    }
    Test-Case 'Malformed header, record, GUID, timestamp and UTF8 are rejected' {
        foreach ($text in @('wrong header', ([Text.Encoding]::UTF8.GetString($fixture) + "bad`r`n"),
            ([Text.Encoding]::UTF8.GetString($fixture).Replace($positive, 'invalid-guid')),
            ([Text.Encoding]::UTF8.GetString($fixture).Replace('2026-10-28T', 'invalid-time-T')))) {
            [IO.File]::WriteAllText("$lab\SharePoint-IncidentDemo-v1.tsv", $text, [Text.UTF8Encoding]::new($false))
            Assert-Throws { & $reader -CorrelationId $positive }
        }
        [IO.File]::WriteAllBytes("$lab\SharePoint-IncidentDemo-v1.tsv", [byte[]]@(0xC3, 0x28))
        Assert-Throws { & $reader -CorrelationId $positive }
    }
    Test-Case 'Missing and locked data are errors, never zero matches' {
        Move-Item "$lab\SharePoint-IncidentDemo-v1.tsv" "$temp\backup.tsv"
        try { Assert-Throws { & $reader -CorrelationId $positive } }
        finally { Move-Item "$temp\backup.tsv" "$lab\SharePoint-IncidentDemo-v1.tsv" }
        $handle = [IO.File]::Open("$lab\SharePoint-IncidentDemo-v1.tsv", 'Open', 'ReadWrite', 'None')
        try { Assert-Throws { & $reader -CorrelationId $positive } }
        finally { $handle.Dispose() }
    }
    Test-Case 'Size and line limits fail explicitly rather than hiding missing coverage' {
        [IO.File]::WriteAllBytes("$lab\SharePoint-IncidentDemo-v1.tsv", [byte[]]::new(1MB + 1))
        Assert-Throws { & $reader -CorrelationId $positive } '1 MiB'
        $header = [Text.Encoding]::UTF8.GetString($fixture).Split("`n")[0]
        $shortRow = @('2026-10-28T10:00:00.000Z', 'S', 'p', 't', 'A', 'C', 'E',
            'Medium', 'SYNTHETIC DEMO: x', $positive) -join "`t"
        [IO.File]::WriteAllText("$lab\SharePoint-IncidentDemo-v1.tsv",
            $header + "`n" + (($shortRow + "`n") * 5001), [Text.UTF8Encoding]::new($false))
        Assert-Throws { & $reader -CorrelationId $positive } '5000-record'
    }
    Test-Case 'Directory reparse point is rejected by initializer and reader' {
        Move-Item $lab "$temp\original"
        $null = New-Item -ItemType Junction -Path $lab -Target "$temp\original"
        try {
            Assert-Throws { & $reader -CorrelationId $positive } 'Reparse'
            Assert-Throws { & $initialize -DataGzipBase64 $dataBase64 -ReaderBase64 $readerBase64 } 'normal directory'
        }
        finally { [IO.Directory]::Delete($lab); Move-Item "$temp\original" $lab }
    }
    Test-Case 'Synthetic markers and full-message budgets are enforced' {
        $text = [Text.Encoding]::UTF8.GetString($fixture)
        [IO.File]::WriteAllText("$lab\SharePoint-IncidentDemo-v1.tsv",
            $text.Replace('SYNTHETIC DEMO: ', 'unlabelled: '), [Text.UTF8Encoding]::new($false))
        Assert-Throws { & $reader -CorrelationId $positive } 'synthetic message'
        [IO.File]::WriteAllText("$lab\SharePoint-IncidentDemo-v1.tsv",
            $text.Replace('SYNTHETIC DEMO: ', ('SYNTHETIC DEMO: ' + ('x' * 321))), [Text.UTF8Encoding]::new($false))
        Assert-Throws { & $reader -CorrelationId $positive } 'synthetic message'
    }
    Test-Case 'Invalid compressed data and decompression over 1 MiB are rejected' {
        Assert-Throws { & $initialize -DataGzipBase64 'not-base64' -ReaderBase64 $readerBase64 }
        $stream = [IO.MemoryStream]::new()
        $compress = [IO.Compression.GZipStream]::new($stream, [IO.Compression.CompressionMode]::Compress, $true)
        try {
            $oversize = [byte[]]::new(1MB + 1)
            $compress.Write($oversize, 0, $oversize.Length)
        }
        finally { $compress.Dispose() }
        try { $encoded = [Convert]::ToBase64String($stream.ToArray()) } finally { $stream.Dispose() }
        Assert-Throws { & $initialize -DataGzipBase64 $encoded -ReaderBase64 $readerBase64 } 'Decompressed dataset exceeds'
    }
    Test-Case 'Prompt pins both hashes, preserves approval and marks evidence as untrusted' {
        $prompt = & "$root\scripts\New-IncidentDemoPrompt.ps1" @target
        Assert-True ($prompt.Contains((Get-FileHash $readerPath).Hash) -and
            $prompt.Contains((Get-FileHash $dataPath).Hash)) 'Missing pins.'
        Assert-True ($prompt.Contains('untrusted evidence') -and $prompt.Contains('administrator approval') -and
            $prompt.Contains('Missing pages mean incomplete evidence')) 'Missing investigation guardrails.'
    }
    Test-Case 'WhatIf never invokes Run Command' {
        $result = & "$root\scripts\Initialize-IncidentDemo.ps1" @target -WhatIf
        Assert-True ($null -eq $result -and
            @($global:IncidentDemoTestState.Calls | Where-Object { $_ -like 'vm run-command*' }).Count -eq 0) 'WhatIf mutated the guest.'
    }
    Test-Case 'Confirmed installer stages data outside the CLI command line and verifies exact hashes' {
        $result = & "$root\scripts\Initialize-IncidentDemo.ps1" @target -Confirm:$false
        Assert-True ($result.datasetSha256 -eq (Get-FileHash $dataPath).Hash) 'Installer did not verify dataset.'
        $invoke = @($global:IncidentDemoTestState.Calls | Where-Object { $_ -like 'vm run-command*' })
        Assert-True ($invoke.Count -eq 1 -and $invoke[0].Length -lt 2048 -and
            $invoke[0] -notmatch 'DataGzipBase64=|ReaderBase64=') 'Encoded data leaked into the native command line.'
        Assert-True (-not (Test-Path -LiteralPath $global:IncidentDemoTestState.StagedPath)) 'Staged installer was not cleaned up.'
    }
    foreach ($mode in @('agent-not-ready', 'extension-pending')) {
        Test-Case "Installer stops before guest execution for $mode" {
            $global:IncidentDemoTestState.Mode = $mode
            Assert-Throws { & "$root\scripts\Initialize-IncidentDemo.ps1" @target -Confirm:$false }
            Assert-True (@($global:IncidentDemoTestState.Calls | Where-Object { $_ -like 'vm run-command*' }).Count -eq 0) 'Unsafe setup was invoked.'
        }
    }
    Test-Case 'All scenarios pass manual acceptance with exactly ten mocked reads' {
        $result = @(& "$root\scripts\Test-IncidentDemo.ps1" @target)
        Assert-True ($result.Count -eq 5) 'Missing scenario acceptance.'
        Assert-True (@($global:IncidentDemoTestState.Calls | Where-Object { $_ -like 'vm run-command*' }).Count -eq 10) 'Unexpected paging or retry.'
    }
    foreach ($mode in @('wrong-hash', 'wrong-source', 'wrong-page', 'wrong-count', 'wrong-total',
        'wrong-partial', 'wrong-more', 'wrong-next', 'wrong-time', 'wrong-boolean-type',
        'wrong-integer-type', 'duplicate-lines', 'stderr', 'cli-failure')) {
        Test-Case "Evidence wrapper rejects $mode" {
            $global:IncidentDemoTestState.Mode = $mode
            Assert-Throws { & "$root\scripts\Get-IncidentDemoEvidence.ps1" @target -CorrelationId $positive }
        }
    }
    if ($SkipWindowsPowerShellCompatibility) {
        Write-Warning 'Windows PowerShell 5.1 execution explicitly skipped; guest compatibility remains unverified.'
    }
    else {
        Test-Case 'Windows PowerShell 5.1 runs the unchanged guest script logic' {
            [IO.File]::WriteAllText("$temp\guest-reader.ps1", $reader.ToString())
            [IO.File]::WriteAllText("$temp\guest-initialize.ps1", $initialize.ToString())
            $runner = @"
`$ErrorActionPreference = 'Stop'
function Set-Acl { param(`$LiteralPath, `$AclObject) }
& '$temp\guest-initialize.ps1' -DataGzipBase64 '$dataBase64' -ReaderBase64 '$readerBase64' | Out-Null
& '$temp\guest-reader.ps1' -CorrelationId '$positive'
"@
            [IO.File]::WriteAllText("$temp\guest-runner.ps1", $runner)
            $json = & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -File "$temp\guest-runner.ps1"
            Assert-True ($LASTEXITCODE -eq 0) 'Guest runtime check failed; honor signing policy.'
            Assert-True ((($json -join "`n") | ConvertFrom-Json).totalMatchingRecords -eq 12) 'Wrong guest result.'
        }
    }
    Write-Host "$script:passed incident-demo checks passed; maximum page output $script:maxOutputBytes / 2800 UTF-8 bytes. ACL application and Azure calls were mocked."
}
finally {
    Remove-Variable -Name IncidentDemoTestState -Scope Global -ErrorAction SilentlyContinue
    foreach ($name in @('SharePoint-IncidentDemo-v1.tsv', 'Read-IncidentDemo.ps1')) {
        $path = Join-Path $lab $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    if (Test-Path -LiteralPath $lab -PathType Container) { Remove-Item -LiteralPath $lab }
    foreach ($name in @('regenerated.tsv', 'Synthetic-ULS.log', 'guest-reader.ps1', 'guest-initialize.ps1', 'guest-runner.ps1')) {
        $path = Join-Path $temp $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    if (Test-Path -LiteralPath $temp -PathType Container) { Remove-Item -LiteralPath $temp }
}
