targetScope = 'resourceGroup'

param vmName string

@description('Object/principal ID of the SRE Agent execution managed identity, NOT its client ID.')
param agentPrincipalId string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource commandRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, vm.id, 'SP-SRE-POC1-RunCommand')
  properties: {
    roleName: 'SP SRE POC1 Run Command ${uniqueString(vm.id)}'
    description: 'Privileged SYSTEM command execution. Assign only to the approved lab VM; not a read-only file role.'
    type: 'CustomRole'
    assignableScopes: [resourceGroup().id]
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachines/read'
          'Microsoft.Compute/virtualMachines/instanceView/read'
          'Microsoft.Compute/virtualMachines/runCommand/action'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id, agentPrincipalId, commandRole.id)
  scope: vm
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: commandRole.id
  }
}

output roleDefinitionId string = commandRole.id
output roleAssignmentId string = assignment.id
