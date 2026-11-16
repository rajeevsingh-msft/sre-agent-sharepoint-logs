#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$VmName = 'sp-sre-poc1'
)
. "$PSScriptRoot\Common.ps1"
$dataPath = Join-Path $PSScriptRoot '..\data\SharePoint-IncidentDemo-v1.tsv'
$readerPath = Join-Path $PSScriptRoot 'Read-IncidentDemo.ps1'
$data = [IO.File]::ReadAllBytes($dataPath)
if ($data.Length -eq 0 -or $data.Length -gt 1MB) { throw 'Dataset must be between 1 byte and 1 MiB.' }
$memory = [IO.MemoryStream]::new()
$gzip = [IO.Compression.GZipStream]::new($memory, [IO.Compression.CompressionMode]::Compress, $true)
try { $gzip.Write($data, 0, $data.Length) } finally { $gzip.Dispose() }
try { $dataBase64 = [Convert]::ToBase64String($memory.ToArray()) } finally { $memory.Dispose() }
$readerBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($readerPath))
if ($dataBase64.Length + $readerBase64.Length -gt 24000) {
    throw 'Encoded package exceeds the reviewed 24000-character payload budget.'
}
$subscription = $SubscriptionId.ToString()
$null = Assert-LabVm $subscription $ResourceGroupName $VmName
Assert-LabVmReady $subscription $ResourceGroupName $VmName
if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$VmName",
    'Install separate synthetic incident dataset and reader using SYSTEM Run Command; preserve smoke-test files')) {
    $stagedPath = Join-Path ([IO.Path]::GetTempPath()) ('sp-incident-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $guest = [IO.File]::ReadAllText("$PSScriptRoot\Initialize-IncidentDemoGuest.ps1")
    $stagedScript = "& {`n$guest`n} -DataGzipBase64 '$dataBase64' -ReaderBase64 '$readerBase64'`n"
    try {
        $handle = [IO.File]::Open($stagedPath, 'CreateNew', 'Write', 'None')
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($stagedScript)
            $handle.Write($bytes, 0, $bytes.Length)
        }
        finally { $handle.Dispose() }
        $result = Invoke-LabCommand $subscription $ResourceGroupName $VmName "@$stagedPath"
    }
    finally {
        if (Test-Path -LiteralPath $stagedPath) { Remove-Item -LiteralPath $stagedPath }
    }
    if ($result.kind -ne 'uls-incident-demo-initialized' -or $result.synthetic -ne $true -or
        $result.datasetVersion -ne 'v1' -or
        $result.file -ne 'C:\SP-SRE-Lab\IncidentDemo-v1\SharePoint-IncidentDemo-v1.tsv' -or
        $result.readerPath -ne 'C:\SP-SRE-Lab\IncidentDemo-v1\Read-IncidentDemo.ps1' -or
        $result.datasetSha256 -ne (Get-FileHash $dataPath).Hash -or
        $result.readerSha256 -ne (Get-FileHash $readerPath).Hash) {
        throw 'Incident-demo initialization did not return the expected paths and hashes.'
    }
    $result
}
