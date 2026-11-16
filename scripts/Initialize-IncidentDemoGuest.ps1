#requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$DataGzipBase64,
    [Parameter(Mandatory = $true)][string]$ReaderBase64
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$folder = 'C:\SP-SRE-Lab\IncidentDemo-v1'
$readerBytes = [Convert]::FromBase64String($ReaderBase64)
$compressed = [Convert]::FromBase64String($DataGzipBase64)
if ($readerBytes.Length -eq 0 -or $readerBytes.Length -gt 32KB -or
    $compressed.Length -eq 0 -or $compressed.Length -gt 32KB) { throw 'Invalid demo package size.' }
$inputStream = [IO.MemoryStream]::new($compressed, $false)
$outputStream = [IO.MemoryStream]::new()
$gzip = [IO.Compression.GZipStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
try {
    $buffer = New-Object byte[] 4096
    while (($count = $gzip.Read($buffer, 0, $buffer.Length)) -gt 0) {
        if ($outputStream.Length + $count -gt 1MB) { throw 'Decompressed dataset exceeds 1 MiB.' }
        $outputStream.Write($buffer, 0, $count)
    }
    $dataBytes = $outputStream.ToArray()
}
finally { $gzip.Dispose(); $inputStream.Dispose(); $outputStream.Dispose() }
$dataText = [Text.UTF8Encoding]::new($false, $true).GetString($dataBytes)
if (-not $dataText.StartsWith("Timestamp`tServer`tProcess`tTID`tArea`tCategory`tEventID`tLevel`tMessage`tCorrelation`r`n") -or
    -not $dataText.Contains('SYNTHETIC DEMO: ')) { throw 'Not the expected synthetic dataset.' }
$files = @(
    @{ Path = (Join-Path $folder 'SharePoint-IncidentDemo-v1.tsv'); Bytes = $dataBytes },
    @{ Path = (Join-Path $folder 'Read-IncidentDemo.ps1'); Bytes = $readerBytes }
)
foreach ($directory in @((Split-Path $folder -Parent), $folder)) {
    if (Test-Path -LiteralPath $directory) {
        $item = Get-Item -LiteralPath $directory -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Expected a normal directory: $directory"
        }
    }
}
foreach ($file in $files) {
    if (Test-Path -LiteralPath $file.Path) {
        $item = Get-Item -LiteralPath $file.Path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $item.Length -ne $file.Bytes.Length -or
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.Path)) -ne [Convert]::ToBase64String($file.Bytes)) {
            throw "Existing demo file differs; not overwriting: $($file.Path). Review before upgrade."
        }
    }
}
$null = [IO.Directory]::CreateDirectory($folder)
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
    $identity = New-Object Security.Principal.SecurityIdentifier($sid)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
}
Set-Acl -LiteralPath $folder -AclObject $acl
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file.Path)) {
        $handle = [IO.File]::Open($file.Path, 'CreateNew', 'Write', 'None')
        try { $handle.Write($file.Bytes, 0, $file.Bytes.Length) } finally { $handle.Dispose() }
    }
    $fileAcl = Get-Acl -LiteralPath $file.Path
    $fileAcl.SetAccessRuleProtection($false, $false)
    foreach ($rule in @($fileAcl.Access | Where-Object { -not $_.IsInherited })) {
        $null = $fileAcl.RemoveAccessRuleSpecific($rule)
    }
    Set-Acl -LiteralPath $file.Path -AclObject $fileAcl
}
[pscustomobject]@{
    kind = 'uls-incident-demo-initialized'; synthetic = $true; datasetVersion = 'v1'
    file = $files[0].Path; readerPath = $files[1].Path
    datasetSha256 = (Get-FileHash -LiteralPath $files[0].Path -Algorithm SHA256).Hash
    readerSha256 = (Get-FileHash -LiteralPath $files[1].Path -Algorithm SHA256).Hash
} | ConvertTo-Json -Compress
