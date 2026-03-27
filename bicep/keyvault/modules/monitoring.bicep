// ==========================================
// Parameters
// ==========================================

// Name of the Key Vault
param kvName string

// Enable / disable monitoring
param enableMonitoring bool = true

// ==========================================
// Existing resources
// ==========================================

// Reference existing Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

// ==========================================
// Log Analytics Workspace (only if enabled)
// ==========================================

resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring) {
  name: 'law-${kvName}'
  location: resourceGroup().location
  properties: {
    // Retention in days (minimum allowed is 5)
    retentionInDays: 30
  }
}

// ==========================================
// Diagnostic Settings (only if enabled)
// ==========================================

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'kv-diagnostics'
  scope: kv

  properties: {
    // Destination for logs
    workspaceId: law.id

    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]

    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
