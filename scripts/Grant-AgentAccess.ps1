#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$VmName = 'sp-sre-poc1',
    [Parameter(Mandatory)][guid]$AgentPrincipalId,
    [ValidateSet('Preview', 'Deploy')][string]$Mode = 'Preview'
)
. "$PSScriptRoot\Common.ps1"
$null = Assert-LabVm $SubscriptionId.ToString() $ResourceGroupName $VmName
$arguments = @('--subscription', $SubscriptionId.ToString(), '--resource-group', $ResourceGroupName,
    '--name', "$VmName-agent-access", '--template-file', "$PSScriptRoot\..\infra\agent-access.bicep",
    '--parameters', "vmName=$VmName", "agentPrincipalId=$AgentPrincipalId", '--only-show-errors')
& az deployment group what-if @arguments
if ($LASTEXITCODE -ne 0) { throw 'Agent RBAC preview failed. No permissions were assigned.' }
if ($Mode -eq 'Deploy' -and $PSCmdlet.ShouldProcess("$AgentPrincipalId on $VmName", 'Grant privileged Run Command execution as SYSTEM (not read-only)')) {
    & az deployment group create @arguments --output json
    if ($LASTEXITCODE -ne 0) { throw 'RBAC deployment failed. Inspect partial role/assignment state before retrying.' }
}
