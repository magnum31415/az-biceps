param kvName string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: '${kv.name}/test-secret'
  properties: {
    value: 'dummy-value'
    attributes: {
      enabled: true
      exp: dateTimeAdd(utcNow(), 'P2Y')
    }
  }
}
