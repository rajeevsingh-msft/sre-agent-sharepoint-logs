#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_-]{1,80}$')][string]$ResourceGroupName,
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{2,13}[a-zA-Z0-9]$')][string]$VmName = 'sp-sre-poc1',
    [Parameter(Mandatory)][guid]$CorrelationId,
    [ValidateRange(0, 1000)][int]$Page = 0
)
. "$PSScriptRoot\Common.ps1"
$subscription = $SubscriptionId.ToString()
$target = @{ SubscriptionId = $SubscriptionId; ResourceGroupName = $ResourceGroupName; VmName = $VmName }
$null = Assert-LabVm $subscription $ResourceGroupName $VmName
Assert-LabVmReady $subscription $ResourceGroupName $VmName
$payload = & "$PSScriptRoot\New-IncidentDemoPrompt.ps1" @target -CorrelationId $CorrelationId -Page $Page -PayloadOnly
$result = Invoke-LabCommand $subscription $ResourceGroupName $VmName $payload
# Newer PowerShell releases deserialize ISO UTC timestamps as DateTime.
if ($result.queryUtc -is [datetime] -and $result.queryUtc.Kind -eq [DateTimeKind]::Utc) {
    $result.queryUtc = $result.queryUtc.ToString('o')
}
foreach ($name in @('kind', 'datasetVersion', 'source', 'file', 'datasetSha256', 'correlationId', 'queryUtc', 'coverage')) {
    if ($result.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($result.$name)) {
        throw "Expected a nonempty incident evidence string: $name"
    }
}
foreach ($name in @('synthetic', 'hasMore', 'partial', 'scanComplete')) {
    if ($result.$name -isnot [bool]) { throw "Expected an incident evidence Boolean: $name" }
}
foreach ($name in @('page', 'pageSize', 'totalMatchingRecords', 'matchingRecordsReturned')) {
    if (($result.$name -isnot [int] -and $result.$name -isnot [long]) -or $result.$name -lt 0) {
        throw "Expected a nonnegative incident evidence integer: $name"
    }
}
if ($result.hasMore -and $result.nextPage -isnot [int] -and $result.nextPage -isnot [long]) {
    throw 'Expected an integer continuation page.'
}
$expectedCount = [Math]::Min(4, [Math]::Max(0, $result.totalMatchingRecords - $Page * 4))
$expectedMore = (($Page + 1) * 4) -lt $result.totalMatchingRecords
$expectedNext = if ($expectedMore) { $Page + 1 } else { $null }
if ($result.kind -ne 'uls-incident-demo-evidence' -or $result.synthetic -ne $true -or
    $result.datasetVersion -ne 'v1' -or $result.correlationId -ne $CorrelationId.ToString() -or
    $result.file -ne 'C:\SP-SRE-Lab\IncidentDemo-v1\SharePoint-IncidentDemo-v1.tsv' -or
    $result.datasetSha256 -ne (Get-FileHash "$PSScriptRoot\..\data\SharePoint-IncidentDemo-v1.tsv").Hash -or
    [string]::IsNullOrWhiteSpace($result.source) -or $result.source -ine $VmName -or
    $result.page -ne $Page -or $result.pageSize -ne 4 -or $result.scanComplete -ne $true -or
    $result.totalMatchingRecords -lt 0 -or
    ($Page -gt 0 -and $Page * 4 -ge $result.totalMatchingRecords) -or
    $result.matchingRecordsReturned -ne @($result.evidence).Count -or
    $result.matchingRecordsReturned -ne $expectedCount -or $result.hasMore -ne $expectedMore -or
    $result.nextPage -ne $expectedNext -or
    $result.partial -ne ($expectedCount -lt $result.totalMatchingRecords)) {
    throw 'Guest incident evidence does not match the requested page, source, dataset and count contract.'
}
if ($result.queryUtc -notmatch 'Z$') { throw 'Expected a UTC query timestamp.' }
$null = [datetimeoffset]::Parse($result.queryUtc, [cultureinfo]::InvariantCulture)
if (@($result.evidence | Select-Object -ExpandProperty lineNumber -Unique).Count -ne $expectedCount) {
    throw 'Incident page contains duplicate line references.'
}
foreach ($record in $result.evidence) {
    if ($record.lineNumber -lt 2 -or $record.message -notlike 'SYNTHETIC DEMO: *' -or
        $record.message.Length -gt 320 -or [string]::IsNullOrWhiteSpace($record.eventId)) {
        throw 'Incident page contains an invalid evidence record.'
    }
}
$result
