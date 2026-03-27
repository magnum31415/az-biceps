param kvName string
param email string

resource actionGroup 'Microsoft.Insights/actionGroups@2022-06-01' = {
  name: 'ag-kv-alerts'
  location: 'global'
  properties: {
    groupShortName: 'kv-alert'
    enabled: true
    emailReceivers: [
      {
        name: 'email'
        emailAddress: email
      }
    ]
  }
}

resource alert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'kv-delete-alert'
  location: 'global'
  properties: {
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'operationName'
          equals: 'Microsoft.KeyVault/vaults/delete'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}
