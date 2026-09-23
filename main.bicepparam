using './main.bicep'

// Replace every <...> value before deploying.

param accountName = '<cosmos-account-name>'
param location = 'region'
param zoneRedundant = false

param privateEndpointSubnetId = '/subscriptions/<sub-id>/resourceGroups/<network-rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<pe-subnet>'

param gremlinPrivateDnsZoneId = '/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.gremlin.cosmos.azure.us'
param sqlPrivateDnsZoneId = '/subscriptions/<sub-id>/resourceGroups/<dns-rg>/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.us'

param sentinelWorkspaceId = '/subscriptions/<sub-id>/resourceGroups/<sentinel-rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>'

// Must be in the same resource group as the Cosmos account
param keyVaultName = '<key-vault-name>'

param databaseName = 'graphdb'
param graphName = 'graph1'
param partitionKeyPath = '/pk'
param maxAutoscaleThroughput = 1000

param enableFullTextQuery = false
param logDataPlaneRequests = true

param tags = {
  environment: 'prod'
  compliance: 'cmmc-l2'
}
