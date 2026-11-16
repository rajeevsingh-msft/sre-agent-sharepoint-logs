#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\data\SharePoint-IncidentDemo-v1.tsv')
)
$ErrorActionPreference = 'Stop'
$rows = [Collections.Generic.List[object]]::new()
$start = [datetime]::Parse('2026-10-28T09:55:00Z', [cultureinfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::AdjustToUniversal)
function Add-Event {
    param([datetime]$Time, [string]$Server, [string]$Process, [string]$Area,
        [string]$Category, [string]$EventId, [string]$Level, [string]$Message, [string]$Correlation)
    if ($Message.Length -gt 300 -or $Message -match "[`t`r`n]") { throw 'Invalid synthetic message.' }
    $rows.Add([pscustomobject][ordered]@{
        Timestamp = $Time.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [cultureinfo]::InvariantCulture)
        Server = $Server; Process = $Process; TID = '0x1A40'; Area = $Area
        Category = $Category; EventID = $EventId; Level = $Level
        Message = "SYNTHETIC DEMO: $Message"; Correlation = $Correlation
    })
}
for ($i = 1; $i -le 600; $i++) {
    $server = if ($i % 2 -eq 0) { 'SP-WFE-DEMO01' } else { 'SP-WFE-DEMO02' }
    Add-Event $start.AddSeconds($i * 5) $server 'w3wp.exe (0x1600)' 'SharePoint Foundation' `
        'Request Management' 'dn001' 'Medium' `
        "GET https://portal.example.invalid/sites/demo/item/$i completed; HTTP 200; durationMs=$($i % 80 + 20)." `
        ('{0:x8}-0000-4000-8000-{0:x12}' -f $i)
}
$cases = @(
    @{
        Id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'; Time = $start.AddMinutes(5)
        Events = @(
            '0|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Request Management|ds001|Medium|GET https://portal.example.invalid/sites/demo/documents started.',
            '20|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Authentication Authorization|ds002|Medium|Claims token accepted; request authorized.',
            '40|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Database|ds003|Medium|Opening connection to SQL-DEMO01; database=SP_Content_Demo; connectTimeoutSeconds=30.',
            '30040|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Database|ds004|Unexpected|System.Data.SqlClient.SqlException: connection timeout expired before opening connection; server=SQL-DEMO01; database=SP_Content_Demo.',
            '30050|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Database|ds005|High|Provider=TCP Provider; nativeError=10060; connection attempt received no response. Database credentials were not validated.',
            '30060|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Database|ds006|High|Stack: SqlConnection.Open -> SPRequest.OpenWeb. No query execution was recorded for this attempt.',
            '30100|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Database|ds007|Medium|Application retry 1 of 1; opening connection to the same SQL endpoint.',
            '60100|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Database|ds008|Unexpected|Retry failed with connection timeout; server=SQL-DEMO01; nativeError=10060.',
            '60110|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Runtime|ds009|Unexpected|SPException: content database operation unavailable; inner exception=SqlException. Request processing aborted.',
            '60120|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Request Management|ds010|High|HTTP 500 returned for /sites/demo/documents; elapsedMs=60120; database connection was never established.',
            '60130|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Monitoring|ds011|Medium|Evidence scope: one failed request. SQL host health, DNS resolution and firewall state were not collected.',
            '60140|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Monitoring|ds012|Medium|No recovery verification exists in this correlation. Do not infer a stopped SQL service or a repaired incident.'
        )
    },
    @{
        Id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'; Time = $start.AddMinutes(15)
        Events = @(
            '0|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Request Management|da001|Medium|GET https://portal.example.invalid/sites/claims started; authentication required.',
            '10|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Claims Authentication|da002|Medium|Requesting security token from the farm security token service.',
            '20|SP-APP-DEMO01|w3wp.exe (0x3100)|SharePoint Foundation|Security Token Service|da003|High|Token-signing certificate chain validation failed; chainStatus=UntrustedRoot.',
            '30|SP-APP-DEMO01|w3wp.exe (0x3100)|SharePoint Foundation|Security Token Service|da004|Unexpected|SecurityTokenValidationException: signing certificate chain is not trusted. Token issuance failed.',
            '40|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Claims Authentication|da005|Unexpected|Security token service returned token validation failure; user session was not established.',
            '50|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Authentication Authorization|da006|High|HTTP 401 returned; downstream content database lookup was not attempted.',
            '60|SP-APP-DEMO01|w3wp.exe (0x3100)|SharePoint Foundation|Monitoring|da007|Medium|Certificate expiry, trust-store contents and recent certificate changes were not collected.',
            '70|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Monitoring|da008|Medium|Evidence scope: this claims request only. No password rejection, certificate expiry or SQL outage is established.'
        )
    },
    @{
        Id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3'; Time = $start.AddMinutes(25)
        Events = @(
            '0|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Server Search|Query|dq001|Medium|Search request started for /sites/demo/search; queryText=[synthetic test query].',
            '10|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Foundation|Authentication Authorization|dq002|Medium|Claims validation succeeded; search request authorized.',
            '20|SP-APP-DEMO01|noderunner.exe (0x4100)|SharePoint Server Search|Query Processing|dq003|Medium|Dispatching query to query component SEARCH-DEMO01; timeoutSeconds=15.',
            '15020|SP-APP-DEMO01|noderunner.exe (0x4100)|SharePoint Server Search|Query Processing|dq004|Unexpected|Query component request timed out; endpoint=SEARCH-DEMO01; no response within 15000 ms.',
            '15030|SP-APP-DEMO01|noderunner.exe (0x4100)|SharePoint Server Search|Topology|dq005|High|No query component available to this query processor; cached topology state=Degraded.',
            '15040|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Server Search|Query|dq006|Unexpected|Search query failed; HTTP 503; elapsedMs=15040. Content database availability was not tested.',
            '15050|SP-APP-DEMO01|noderunner.exe (0x4100)|SharePoint Server Search|Monitoring|dq007|Medium|Live topology, component process state and index health were not collected.',
            '15060|SP-WFE-DEMO01|w3wp.exe (0x1600)|SharePoint Server Search|Monitoring|dq008|Medium|Evidence supports query-component unavailability for this request, not confirmed index corruption or farm-wide failure.'
        )
    },
    @{
        Id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd4'; Time = $start.AddMinutes(35)
        Events = @(
            '0|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Request Management|dh001|Medium|GET https://portal.example.invalid/sites/demo/home started.',
            '10|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Authentication Authorization|dh002|Medium|Claims token validated and request authorized.',
            '20|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Database|dh003|Medium|Connection opened to SQL-DEMO01; database=SP_Content_Demo; durationMs=8.',
            '30|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Database|dh004|Medium|Content lookup completed; rows=1; durationMs=6.',
            '40|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Runtime|dh005|Medium|Page render completed; cacheStatus=Hit.',
            '50|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Request Management|dh006|Medium|HTTP 200 returned; elapsedMs=50.',
            '60|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Monitoring|dh007|Medium|No High or Unexpected events in this correlation.',
            '70|SP-WFE-DEMO02|w3wp.exe (0x2200)|SharePoint Foundation|Monitoring|dh008|Medium|One successful request does not establish farm-wide health or recovery of an earlier request.'
        )
    }
)
foreach ($case in $cases) {
    foreach ($event in $case.Events) {
        $parts = $event.Split('|')
        if ($parts.Count -ne 8) { throw 'Invalid scenario definition.' }
        Add-Event $case.Time.AddMilliseconds([int]$parts[0]) $parts[1] $parts[2] $parts[3] `
            $parts[4] $parts[5] $parts[6] $parts[7] $case.Id
    }
}
Add-Event $start.AddMinutes(5).AddSeconds(1) 'SP-WFE-DEMO02' 'w3wp.exe (0x2200)' `
    'SharePoint Foundation' 'Database' 'noise1' 'High' `
    'Unrelated database query warning; different request; do not merge by message text.' 'ffffffff-ffff-4fff-8fff-fffffffffff1'
Add-Event $start.AddMinutes(15).AddSeconds(1) 'SP-WFE-DEMO01' 'w3wp.exe (0x1600)' `
    'SharePoint Foundation' 'Claims Authentication' 'noise2' 'Unexpected' `
    'Unrelated claims failure; different request; do not merge by severity.' 'ffffffff-ffff-4fff-8fff-fffffffffff2'
$columns = @('Timestamp', 'Server', 'Process', 'TID', 'Area', 'Category', 'EventID', 'Level', 'Message', 'Correlation')
$lines = [Collections.Generic.List[string]]::new()
$lines.Add(($columns -join "`t"))
foreach ($row in $rows | Sort-Object Timestamp, Server, EventID) {
    $values = @($columns | ForEach-Object { [string]$row.$_ })
    if (@($values | Where-Object { $_ -match "[`t`r`n]" }).Count -gt 0) { throw 'Invalid TSV field.' }
    $lines.Add(($values -join "`t"))
}
$path = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $path) { throw "Not overwriting existing dataset: $path" }
if ($PSCmdlet.ShouldProcess($path, 'Create deterministic synthetic incident dataset')) {
    $null = [IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`r`n") + "`r`n")
    $stream = [IO.File]::Open($path, 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    [pscustomobject]@{ synthetic = $true; path = $path; records = $rows.Count; sha256 = (Get-FileHash $path).Hash }
}
