#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$VmName = 'sp-sre-poc1'
)
$ErrorActionPreference = 'Stop'
$target = @{ SubscriptionId = $SubscriptionId; ResourceGroupName = $ResourceGroupName; VmName = $VmName }
foreach ($case in @(
    @{ Id = '11111111-1111-1111-1111-111111111111'; Count = 2 },
    @{ Id = '33333333-3333-3333-3333-333333333333'; Count = 0 }
)) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = & "$PSScriptRoot\Get-LabEvidence.ps1" @target -CorrelationId $case.Id
    $watch.Stop()
    if ($result.matchingRecordsReturned -ne $case.Count -or $result.partial -ne $false) {
        throw "Fixture acceptance failed for $($case.Id). Expected $($case.Count) matches and complete coverage."
    }
    [pscustomobject]@{
        correlationId = $case.Id
        expected = $case.Count
        actual = $result.matchingRecordsReturned
        partial = $result.partial
        source = $result.source
        queryUtc = $result.queryUtc
        elapsedSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 1)
        status = 'PASS (manual transport only; not agent acceptance)'
    }
}
