param kvName string
param principalId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

var roles = [
  'Key Vault Secrets Officer'
  'Key Vault Crypto Officer'
  'Key Vault Certificates Officer'
  'Key Vault Contributor'
]

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for role in roles: {
  name: guid(kv.id, principalId, role)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      role
    )
    principalId: principalId
    principalType: 'Group'
  }
}]
