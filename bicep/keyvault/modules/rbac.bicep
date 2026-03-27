param kvName string
param principalId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

var roles = [
  'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Secrets Officer
  '14b46e9e-c2b7-41b4-b07b-48a6ebf60603' // Crypto Officer
  'a4417e6f-fecd-4de8-b567-7b0420556985' // Certificates Officer
  'f25e0fa2-a7c8-4377-a976-54943a77a395' // Key Vault Contributor
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
