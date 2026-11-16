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
    @{ Id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'; Count = 12; Name = 'SQL connection timeouts' },
    @{ Id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'; Count = 8; Name = 'Claims certificate trust failure' },
    @{ Id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3'; Count = 8; Name = 'Search query unavailable' },
    @{ Id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4'; Count = 8; Name = 'Successful request control' },
    @{ Id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'; Count = 0; Name = 'Absent correlation' }
)) {
    $seen = [Collections.Generic.HashSet[int]]::new()
    $page = 0
    $hash = $null
    do {
        $result = & "$PSScriptRoot\Get-IncidentDemoEvidence.ps1" @target -CorrelationId $case.Id -Page $page
        if ($result.totalMatchingRecords -ne $case.Count -or
            ($null -ne $hash -and $hash -ne $result.datasetSha256)) { throw "Unexpected dataset/count for $($case.Name)." }
        $hash = $result.datasetSha256
        foreach ($record in $result.evidence) {
            if (-not $seen.Add($record.lineNumber)) { throw 'Duplicate record across pages.' }
        }
        $page++
        if ($page -gt 3) { throw 'Unexpected page count for the reviewed fixture.' }
    } while ($result.hasMore)
    if ($seen.Count -ne $case.Count) { throw "Incomplete retrieval for $($case.Name)." }
    [pscustomobject]@{ scenario = $case.Name; records = $seen.Count; pages = $page
        status = 'PASS (manual transport only; not agent acceptance)' }
}
