#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$VmName = 'sp-sre-poc1'
)
. "$PSScriptRoot\Common.ps1"
$subscription = $SubscriptionId.ToString()
$null = Assert-LabVm $subscription $ResourceGroupName $VmName
Assert-LabVmReady $subscription $ResourceGroupName $VmName
if ($PSCmdlet.ShouldProcess("$ResourceGroupName/$VmName", 'Install synthetic logs and fixed PowerShell reader using privileged Run Command')) {
    $reader = [IO.File]::ReadAllBytes("$PSScriptRoot\Read-UlsLab.ps1")
    $result = Invoke-LabCommand $subscription $ResourceGroupName $VmName `
        "@$PSScriptRoot\Initialize-UlsLab.ps1" @("ReaderBase64=$([Convert]::ToBase64String($reader))")
    if ($result.kind -ne 'uls-lab-initialized' -or -not $result.synthetic -or
        $result.readerSha256 -ne (Get-FileHash "$PSScriptRoot\Read-UlsLab.ps1" -Algorithm SHA256).Hash) {
        throw 'Initialization did not return the expected reader hash and fixture status.'
    }
    $result
}
