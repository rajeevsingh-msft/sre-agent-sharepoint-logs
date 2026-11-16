param(
    [Parameter(Mandatory = $true)]
    [guid]$CorrelationId
)
$ErrorActionPreference = 'Stop'
$folder = 'C:\SP-SRE-Lab'
$path = Join-Path $folder 'Synthetic-ULS.log'
$stream = $null
$reader = $null
try {
    foreach ($itemPath in @($folder, $path)) {
        $item = Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Reparse points are not permitted in the fixed lab source.'
        }
    }
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($stream.Length -gt 1MB) { throw 'Source exceeds the 1 MiB scan budget.' }
    $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true)
    $hits = @()
    $linesRead = 0
    while (-not $reader.EndOfStream -and $linesRead -lt 10000) {
        $line = $reader.ReadLine()
        $linesRead++
        if ($line.IndexOf($CorrelationId.ToString(), [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $hits += [pscustomobject]@{
                lineNumber = $linesRead
                fragment = $line.Substring(0, [Math]::Min(180, $line.Length))
            }
            if ($hits.Count -ge 3) { break }
        }
    }
    $result = [pscustomobject]@{
        kind = 'uls-lab-evidence'
        synthetic = $true
        source = $env:COMPUTERNAME
        file = $path
        correlationId = $CorrelationId.ToString()
        queryUtc = [DateTime]::UtcNow.ToString('o')
        linesRead = $linesRead
        matchingRecordsReturned = $hits.Count
        partial = -not $reader.EndOfStream
        coverage = 'One synthetic file; max 1 MiB / 10000 lines / 3 matches; shortened fragments; no time filter or redaction.'
        evidence = @($hits)
    }
    $json = $result | ConvertTo-Json -Depth 5 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 2500) { throw 'Evidence exceeds the 2500-byte output budget.' }
    Write-Output $json
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    elseif ($null -ne $stream) { $stream.Dispose() }
}
