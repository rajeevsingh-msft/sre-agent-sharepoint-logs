#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-LabAz {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE): az $($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' '). No automatic retry was attempted."
    }
    if (-not $output) { throw 'Azure CLI returned no JSON.' }
    return ($output -join "`n" | ConvertFrom-Json -Depth 64)
}

function Assert-LabVm {
    param([string]$SubscriptionId, [string]$ResourceGroupName, [string]$VmName)
    $vm = Invoke-LabAz @('vm', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName, '--name', $VmName)
    if ($null -eq $vm.tags -or
        -not $vm.tags.PSObject.Properties['purpose'] -or
        -not $vm.tags.PSObject.Properties['environment'] -or
        $vm.tags.purpose -ne 'SP-SRE-POC1' -or
        $vm.tags.environment -ne 'nonproduction' -or
        $vm.storageProfile.osDisk.osType -ne 'Windows') {
        throw 'Target must be the approved, tagged nonproduction Windows lab VM. Tags are a safety check, not an authorization boundary.'
    }
    return $vm
}

function ConvertFrom-LabCommandResult {
    param([Parameter(Mandatory)]$Result)
    $entries = @($Result.value)
    if ($entries.Count -eq 0) { throw 'Run Command returned no status entries.' }
    foreach ($entry in $entries) {
        if ($entry.code -notlike '*/succeeded') {
            throw "Guest command status is not successful: $($entry.code). Check VM status before retrying."
        }
        if ($entry.code -like '*/StdErr/*' -and
            -not [string]::IsNullOrWhiteSpace($entry.message)) {
            throw "Guest command reported stderr: $($entry.message)"
        }
    }
    $stdout = @($entries | Where-Object code -Like '*/StdOut/*')
    if ($stdout.Count -ne 1 -or [string]::IsNullOrWhiteSpace($stdout[0].message)) {
        $codes = ($entries | ForEach-Object code) -join ', '
        throw "Expected exactly one nonempty guest stdout result. Found $($stdout.Count) stdout entries; status codes: $codes. Inspect VM command status before retrying."
    }
    if ([Text.Encoding]::UTF8.GetByteCount($stdout[0].message) -gt 3000) {
        throw 'Guest stdout exceeds the transport safety budget.'
    }
    return ($stdout[0].message | ConvertFrom-Json -Depth 16)
}

function Assert-LabVmReady {
    param([string]$SubscriptionId, [string]$ResourceGroupName, [string]$VmName)
    $view = Invoke-LabAz @('vm', 'get-instance-view', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName, '--name', $VmName)
    if (@($view.instanceView.statuses | Where-Object code -EQ 'PowerState/running').Count -ne 1 -or
        @($view.instanceView.statuses | Where-Object code -EQ 'ProvisioningState/succeeded').Count -ne 1 -or
        @($view.instanceView.vmAgent.statuses | Where-Object code -EQ 'ProvisioningState/succeeded').Count -ne 1) {
        throw 'VM must be running, successfully provisioned and have a Ready VM Agent.'
    }
    $extensions = @(Invoke-LabAz @('vm', 'extension', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName, '--vm-name', $VmName))
    if (@($extensions | Where-Object provisioningState -NE 'Succeeded').Count -gt 0) {
        throw 'An extension is not successfully provisioned. Inspect its status before guest execution.'
    }
}

function Invoke-LabCommand {
    param(
        [string]$SubscriptionId, [string]$ResourceGroupName, [string]$VmName,
        [Parameter(Mandatory)][string]$Script,
        [string[]]$ScriptParameters = @()
    )
    $temporaryScript = $null
    try {
        $scriptArgument = $Script
        if (-not $Script.StartsWith('@', [StringComparison]::Ordinal)) {
            # Windows az.cmd can truncate inline multiline arguments at the first newline.
            $temporaryScript = [IO.Path]::GetTempFileName()
            [IO.File]::WriteAllText($temporaryScript, $Script, [Text.UTF8Encoding]::new($false))
            $scriptArgument = "@$temporaryScript"
        }
        $arguments = @('vm', 'run-command', 'invoke', '--subscription', $SubscriptionId,
            '--resource-group', $ResourceGroupName, '--name', $VmName,
            '--command-id', 'RunPowerShellScript', '--scripts', $scriptArgument)
        if ($ScriptParameters.Count -gt 0) { $arguments += @('--parameters') + $ScriptParameters }
        $result = Invoke-LabAz $arguments
        return ConvertFrom-LabCommandResult $result
    }
    finally {
        if ($temporaryScript) { Remove-Item -LiteralPath $temporaryScript -ErrorAction Stop }
    }
}
