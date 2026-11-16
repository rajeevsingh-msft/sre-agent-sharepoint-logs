#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$VmName = 'sp-sre-poc1',
    [Parameter(Mandatory)][guid]$CorrelationId
)
. "$PSScriptRoot\Common.ps1"
$subscription = $SubscriptionId.ToString()
$null = Assert-LabVm $subscription $ResourceGroupName $VmName
Assert-LabVmReady $subscription $ResourceGroupName $VmName
$hash = (Get-FileHash "$PSScriptRoot\Read-UlsLab.ps1" -Algorithm SHA256).Hash
$script = @"
`$ErrorActionPreference = 'Stop'
`$reader = 'C:\SP-SRE-Lab\Read-UlsLab.ps1'
if ((Get-FileHash -LiteralPath `$reader -Algorithm SHA256).Hash -ne '$hash') {
    throw 'Installed reader hash differs from the reviewed repository version.'
}
& `$reader -CorrelationId '$($CorrelationId.ToString())'
"@
$result = Invoke-LabCommand $subscription $ResourceGroupName $VmName $script
if ($result.queryUtc -is [datetime] -and $result.queryUtc.Kind -eq [DateTimeKind]::Utc) {
    $result.queryUtc = $result.queryUtc.ToString('o')
}
foreach ($name in @('kind', 'source', 'file', 'correlationId', 'queryUtc', 'coverage')) {
    if ($result.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($result.$name)) {
        throw "Expected a nonempty smoke evidence string: $name"
    }
}
foreach ($name in @('synthetic', 'partial')) {
    if ($result.$name -isnot [bool]) { throw "Expected a smoke evidence Boolean: $name" }
}
foreach ($name in @('linesRead', 'matchingRecordsReturned')) {
    if (($result.$name -isnot [int] -and $result.$name -isnot [long]) -or $result.$name -lt 0) {
        throw "Expected a nonnegative smoke evidence integer: $name"
    }
}
if ($result.kind -ne 'uls-lab-evidence' -or $result.synthetic -ne $true -or
    $result.source -ine $VmName -or
    $result.correlationId -ne $CorrelationId.ToString() -or
    $result.file -ne 'C:\SP-SRE-Lab\Synthetic-ULS.log' -or
    $result.linesRead -gt 10000 -or $result.matchingRecordsReturned -gt 3 -or
    $result.evidence -isnot [array] -or
    $result.matchingRecordsReturned -ne @($result.evidence).Count) {
    throw 'Guest evidence does not match the requested lab contract.'
}
if ($result.queryUtc -notmatch 'Z$') { throw 'Expected a UTC query timestamp.' }
$null = [datetimeoffset]::Parse($result.queryUtc, [cultureinfo]::InvariantCulture)
if (@($result.evidence | Select-Object -ExpandProperty lineNumber -Unique).Count -ne $result.matchingRecordsReturned) {
    throw 'Smoke evidence contains duplicate line references.'
}
foreach ($record in $result.evidence) {
    if (($record.lineNumber -isnot [int] -and $record.lineNumber -isnot [long]) -or
        $record.lineNumber -lt 1 -or $record.lineNumber -gt $result.linesRead -or
        $record.fragment -isnot [string] -or [string]::IsNullOrWhiteSpace($record.fragment) -or
        $record.fragment.Length -gt 180) {
        throw 'Smoke evidence contains an invalid evidence record.'
    }
}
$result
