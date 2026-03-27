// ==========================================
// Parameters
// ==========================================

// Name of the Key Vault
// Used for naming resources and scoping alerts
param kvName string

// Email address to receive alert notifications
// Must be a valid email format supported by Azure Monitor
param email string

// ==========================================
// Action Group (email notification)
// ==========================================

resource actionGroup 'Microsoft.Insights/actionGroups@2022-06-01' = {
  // Dynamic name to avoid conflicts across environments
  name: 'ag-kv-alerts-${kvName}'

  // Action Groups are always deployed in 'global'
  location: 'global'

  properties: {
    // Short name used in notifications (max 12 chars recommended)
    groupShortName: 'kv-alert'

    // Enable the action group
    enabled: true

    // Email receivers configuration
    emailReceivers: [
      {
        // Logical name of the receiver
        name: 'email'

        // Email address passed as parameter
        emailAddress: email
      }
    ]
  }
}

// ==========================================
// Activity Log Alert for Key Vault deletion
// ==========================================

resource alert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  // Dynamic naming to avoid conflicts
  name: 'kv-delete-alert-${kvName}'

  location: 'global'

  properties: {
    // Subscription-level scope (required for activity log events)
    scopes: [
      subscription().id
    ]

    condition: {
      allOf: [
        {
          // REQUIRED: category of activity log
          field: 'category'
          equals: 'Administrative'
        }
        {
          // Detect delete operation on Key Vault
          field: 'operationName'
          equals: 'Microsoft.KeyVault/vaults/delete'
        }
        {
          // Limit alert to current Resource Group (reduce noise)
          field: 'resourceGroup'
          equals: resourceGroup().name
        }
      ]
    }

    actions: {
      actionGroups: [
        {
          // Link to the Action Group defined above
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}
