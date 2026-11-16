#requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][guid]$CorrelationId,
    [ValidateRange(0, 1000)][int]$Page = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$folder = 'C:\SP-SRE-Lab\IncidentDemo-v1'
$path = Join-Path $folder 'SharePoint-IncidentDemo-v1.tsv'
$pageSize = 4
$columns = @('Timestamp', 'Server', 'Process', 'TID', 'Area', 'Category', 'EventID', 'Level', 'Message', 'Correlation')
$stream = $null
$reader = $null
try {
    foreach ($itemPath in @((Split-Path $folder -Parent), $folder, $path)) {
        $item = Get-Item -LiteralPath $itemPath -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse points are not permitted.' }
    }
    $stream = [IO.File]::Open($path, 'Open', 'Read', 'Read')
    if ($stream.Length -gt 1MB) { throw 'Dataset exceeds the 1 MiB scan budget.' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $sha.Dispose() }
    $stream.Position = 0
    $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $false)
    if ($reader.ReadLine() -cne ($columns -join "`t")) { throw 'Unexpected incident-demo TSV header.' }
    $evidence = @()
    $total = 0
    $lineNumber = 1
    while (-not $reader.EndOfStream) {
        if ($lineNumber -ge 5001) { throw 'Dataset exceeds the 5000-record scan budget; no partial scan is returned.' }
        $line = $reader.ReadLine()
        $lineNumber++
        $fields = $line.Split("`t")
        if ($fields.Count -ne 10 -or @($fields | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            throw "Malformed TSV record at line $lineNumber."
        }
        if ($fields[8] -notlike 'SYNTHETIC DEMO: *' -or $fields[8].Length -gt 320) {
            throw "Expected a bounded synthetic message at line $lineNumber."
        }
        foreach ($index in @(1, 2, 3, 4, 5, 6, 7)) {
            if ($fields[$index].Length -gt 80) { throw "Oversized field at line $lineNumber." }
        }
        $null = [datetimeoffset]::ParseExact($fields[0], "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
            [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
        $id = [guid]::ParseExact($fields[9], 'D')
        if ($id -ne $CorrelationId) { continue }
        if ($total -ge ($Page * $pageSize) -and $evidence.Count -lt $pageSize) {
            $evidence += [pscustomobject][ordered]@{
                lineNumber = $lineNumber; timestamp = $fields[0]; server = $fields[1]
                process = $fields[2]; tid = $fields[3]; area = $fields[4]; category = $fields[5]
                eventId = $fields[6]; level = $fields[7]; message = $fields[8]
            }
        }
        $total++
    }
    if ($Page -gt 0 -and $Page * $pageSize -ge $total) { throw 'Requested page is outside the matching-record range.' }
    $more = (($Page + 1) * $pageSize) -lt $total
    $next = if ($more) { $Page + 1 } else { $null }
    $result = [pscustomobject][ordered]@{
        kind = 'uls-incident-demo-evidence'; synthetic = $true; datasetVersion = 'v1'
        source = $env:COMPUTERNAME; file = $path; datasetSha256 = $hash
        correlationId = $CorrelationId.ToString(); queryUtc = [datetime]::UtcNow.ToString('o')
        page = $Page; pageSize = $pageSize; totalMatchingRecords = $total
        matchingRecordsReturned = $evidence.Count; hasMore = $more; nextPage = $next
        partial = ($evidence.Count -lt $total); scanComplete = $true
        coverage = 'One synthetic TSV; 1 MiB/5000 records; four full records per page; no time filter; not live farm telemetry.'
        evidence = @($evidence)
    }
    $json = $result | ConvertTo-Json -Depth 5 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 2800) { throw 'Evidence exceeds the 2800-byte output budget.' }
    Write-Output $json
}
finally {
    if ($null -ne $reader) { $reader.Dispose() }
    elseif ($null -ne $stream) { $stream.Dispose() }
}
