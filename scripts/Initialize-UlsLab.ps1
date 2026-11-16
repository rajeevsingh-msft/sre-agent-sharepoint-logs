param(
    [Parameter(Mandatory = $true)]
    [string]$ReaderBase64
)
$ErrorActionPreference = 'Stop'
$folder = 'C:\SP-SRE-Lab'
$logPath = Join-Path $folder 'Synthetic-ULS.log'
$readerPath = Join-Path $folder 'Read-UlsLab.ps1'
$readerBytes = [Convert]::FromBase64String($ReaderBase64)
if ($readerBytes.Length -eq 0 -or $readerBytes.Length -gt 32KB) { throw 'Invalid reader size.' }
$rows = @(
    "Timestamp`tProcess`tLevel`tMessage`tCorrelation"
    "2026-10-21T14:00:00Z`tSyntheticSharePoint`tHigh`tSYNTHETIC ONLY: test service failure`t11111111-1111-1111-1111-111111111111"
    "2026-10-21T14:00:01Z`tSyntheticSharePoint`tUnexpected`tSYNTHETIC ONLY: test dependency unavailable`t11111111-1111-1111-1111-111111111111"
    "2026-10-21T14:01:00Z`tSyntheticSharePoint`tInformation`tSYNTHETIC ONLY: unrelated request`t22222222-2222-2222-2222-222222222222"
)
$logBytes = [Text.UTF8Encoding]::new($false).GetBytes(($rows -join "`r`n") + "`r`n")
if (Test-Path -LiteralPath $folder) {
    $item = Get-Item -LiteralPath $folder -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Lab directory must be a normal directory, not a reparse point.'
    }
}
else {
    $null = New-Item -ItemType Directory -Path $folder
}
$files = @(
    @{ Path = $logPath; Bytes = $logBytes },
    @{ Path = $readerPath; Bytes = $readerBytes }
)
foreach ($file in $files) {
    if (Test-Path -LiteralPath $file.Path) {
        $item = Get-Item -LiteralPath $file.Path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Expected a normal file: $($file.Path)"
        }
        if ($item.Length -gt 32KB -or
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.Path)) -ne [Convert]::ToBase64String($file.Bytes)) {
            throw "Existing file differs; not overwriting: $($file.Path). Review it before cleanup or upgrade."
        }
    }
}
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
    $identity = New-Object Security.Principal.SecurityIdentifier($sid)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $folder -AclObject $acl
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Path)) {
        $handle = [IO.File]::Open($file.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $handle.Write($file.Bytes, 0, $file.Bytes.Length) }
        finally { $handle.Dispose() }
    }
    $fileAcl = Get-Acl -LiteralPath $file.Path
    $fileAcl.SetAccessRuleProtection($false, $false)
    foreach ($rule in @($fileAcl.Access | Where-Object { -not $_.IsInherited })) {
        $null = $fileAcl.RemoveAccessRuleSpecific($rule)
    }
    Set-Acl -LiteralPath $file.Path -AclObject $fileAcl
}
[pscustomobject]@{
    kind = 'uls-lab-initialized'
    synthetic = $true
    file = $logPath
    readerPath = $readerPath
    readerSha256 = (Get-FileHash -LiteralPath $readerPath -Algorithm SHA256).Hash
} | ConvertTo-Json -Compress
