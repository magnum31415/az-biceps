param kvName string
param location string
param tenantId string
param kvAdminsGroupId string
param alertEmail string
param resourceGroupName string
param softDeleteRetentionDays int = 2


module keyvault 'modules/keyvault.bicep' = {
  name: 'deployKeyVault'
  params: {
    kvName: kvName
    location: location
    tenantId: tenantId
    softDeleteRetentionDays: softDeleteRetentionDays
  }
}


module rbac 'modules/rbac.bicep' = {
  name: 'assignRBAC'
  dependsOn: [ keyvault ]
  params: {
    kvName: kvName
    principalId: kvAdminsGroupId
  }
}



module alerts 'modules/alerts.bicep' = {
  name: 'deployAlerts'
  dependsOn: [ keyvault ]
  params: {
    kvName: kvName
    email: alertEmail
  }
}
/*

module monitoring 'modules/monitoring.bicep' = {
  name: 'deployMonitoring'
  dependsOn: [ keyvault ]
  params: {
    kvName: kvName
  }
}
*/
