#requires -Version 7.0
[CmdletBinding()]
param()
. "$PSScriptRoot\Common.ps1"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Host '[1/6] Checking tools and the approved Azure target...'
$null = Get-Command az, azd -ErrorAction Stop
& az bicep version
if ($LASTEXITCODE -ne 0) { throw 'Install the approved Azure CLI Bicep component before running azd up.' }
$settings = Get-PocAzdConfiguration -Prompt
$subscription = $settings.AZURE_SUBSCRIPTION_ID
$tenant = $settings.POC1_TENANT_ID
$accounts = Invoke-LabAz @('account', 'list')
if (@($accounts | Where-Object { $_.id -eq $subscription -and $_.tenantId -eq $tenant }).Count -eq 0) {
    Confirm-PocAzdAction 'Azure CLI needs interactive sign-in for this tenant/subscription. No default CLI subscription will be changed by this hook.' 'LOGIN'
    $target = & "$root\scripts\Initialize-LabContext.ps1" -TenantId $tenant -SubscriptionId $subscription `
        -ResourceGroupName $settings.ResourceGroupName -VmName $settings.VmName -SignIn
} else {
    $target = & "$root\scripts\Initialize-LabContext.ps1" -TenantId $tenant -SubscriptionId $subscription `
        -ResourceGroupName $settings.ResourceGroupName -VmName $settings.VmName
}
Confirm-PocAzdAction "Verify the displayed tenant, subscription and target. Region: $($settings.AZURE_LOCATION); VM size: $($settings.POC1_VM_SIZE)." 'TARGET'

Write-Host '[2/6] Checking providers, VM availability, quota and image...'
foreach ($provider in @('Microsoft.Compute', 'Microsoft.Network')) {
    $state = Invoke-LabAz @('provider', 'show', '--subscription', $subscription, '--namespace', $provider)
    if ($state.registrationState -eq 'Registered') { continue }
    if ($state.registrationState -eq 'NotRegistered') {
        Confirm-PocAzdAction "Provider $provider is not registered. Subscription-owner approval is required to register this provider only." 'REGISTER'
    } elseif ($state.registrationState -ne 'Registering') {
        throw "Unexpected $provider state '$($state.registrationState)'. Inspect it before changing registration."
    }
    & az provider register --subscription $subscription --namespace $provider --wait --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) { throw "Registration failed for $provider. Inspect its state before retrying." }
}
$check = & "$root\scripts\Test-Preflight.ps1" -SubscriptionId $subscription `
    -Location $settings.AZURE_LOCATION -VmSize $settings.POC1_VM_SIZE
$existingImageVersion = Assert-PocAzdResourceGroup $settings
if ($existingImageVersion) { $check.imageVersion = $existingImageVersion }
Set-PocAzdValue 'POC1_IMAGE_VERSION' $check.imageVersion -EnvironmentName $settings.AZURE_ENV_NAME

Write-Host '[3/6] Previewing infrastructure; provisioning requires approval...'
Write-Host 'Azure CLI will securely prompt for a VM password for what-if. azd separately prompts/caches its secure deployment parameter. Use your approved secret-handling process; never put the password in arguments, environment variables or files.'
& az deployment sub what-if --subscription $subscription --location $settings.AZURE_LOCATION `
    --name "poc1-$($settings.AZURE_ENV_NAME)-preview" --template-file "$root\infra\azd\main.bicep" `
    --parameters "environmentName=$($settings.AZURE_ENV_NAME)" "location=$($settings.AZURE_LOCATION)" `
        "vmSize=$($settings.POC1_VM_SIZE)" "imageVersion=$($check.imageVersion)" --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'ARM what-if failed. Provisioning was not approved.' }
Confirm-PocAzdAction 'Review all what-if changes and approved costs for VM, disk, NAT Gateway and public IP. azd may retain the password in its local secret cache: proceed only if your organization approves that storage. No agent grant is included. Continue only for this dedicated disposable lab.' 'PROVISION'
Set-PocAzdValue 'POC1_PROVISION_APPROVED_UTC' ([DateTimeOffset]::UtcNow.ToString('o')) -EnvironmentName $settings.AZURE_ENV_NAME
Write-Host '[3/6] Approved. Returning to azd to provision the infrastructure once...'
