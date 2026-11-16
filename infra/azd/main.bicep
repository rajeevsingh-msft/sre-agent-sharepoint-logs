targetScope = 'subscription'

@minLength(2)
@maxLength(10)
param environmentName string

param location string
// azd initializes parameters before preprovision; the hook supplies the checked values before deployment.
param vmSize string = 'Standard_D2s_v5'
param imageVersion string = ''

@secure()
@minLength(12)
@description('VM administrator password. Use the secure prompt; never set this in an environment variable or source file.')
param adminPassword string

var vmName = 'sp-${environmentName}'
var tags = {
  purpose: 'SP-SRE-POC1'
  environment: 'nonproduction'
  'azd-env-name': environmentName
}

resource lab 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-sp-sre-azd-${environmentName}'
  location: location
  tags: tags
}

module vm '../main.bicep' = {
  name: 'poc1-vm'
  scope: lab
  params: {
    location: location
    vmName: vmName
    vmSize: vmSize
    imageVersion: imageVersion
    adminPassword: adminPassword
    tags: tags
  }
}

output AZURE_RESOURCE_GROUP string = lab.name
output POC1_VM_NAME string = vm.outputs.vmName
output POC1_VM_ID string = vm.outputs.vmId
output POC1_LOG_PATH string = vm.outputs.logPath
output POC1_READER_PATH string = vm.outputs.readerPath
