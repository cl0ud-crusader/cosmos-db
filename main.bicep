// Azure Cosmos DB for Apache Gremlin: private-only, logs to Sentinel workspace
// Target: Azure Government (GCC High). Works in Commercial with matching DNS zone IDs.
targetScope = 'resourceGroup'

// ---------- Parameters ----------

@description('Cosmos DB account name. Globally unique, lowercase letters, digits, hyphens.')
@minLength(3)
@maxLength(44)
param accountName string

@description('Region for the account and private endpoints.')
param location string = resourceGroup().location

@description('Zone redundancy for the write region. Confirm AZ support for Cosmos DB in your Gov region before enabling.')
param zoneRedundant bool = false

@description('Resource ID of the subnet that hosts private endpoints.')
param privateEndpointSubnetId string

@description('Resource ID of the private DNS zone privatelink.gremlin.cosmos.azure.us (Gov) or privatelink.gremlin.cosmos.azure.com (Commercial).')
param gremlinPrivateDnsZoneId string

@description('Resource ID of the private DNS zone privatelink.documents.azure.us (Gov) or privatelink.documents.azure.com (Commercial).')
param sqlPrivateDnsZoneId string

@description('Resource ID of the Sentinel-enabled Log Analytics workspace.')
param sentinelWorkspaceId string

@description('Existing Key Vault in THIS resource group that receives the primary key.')
param keyVaultName string

@description('Gremlin database name.')
param databaseName string = 'graphdb'

@description('Graph (container) name.')
param graphName string = 'graph1'

@description('Partition key path for the graph. Cannot be changed after creation.')
param partitionKeyPath string = '/pk'

@description('Autoscale max RU/s for the graph. Scales between 10 percent of this and this value.')
@minValue(1000)
param maxAutoscaleThroughput int = 1000

@description('Log full Gremlin query text in diagnostics. Query literals may contain CUI.')
param enableFullTextQuery bool = false

@description('Include DataPlaneRequests logs. Highest volume category; drives ingestion cost.')
param logDataPlaneRequests bool = true

param tags object = {}

// ---------- Variables ----------

var gremlinSuffix = environment().name == 'AzureUSGovernment' ? 'gremlin.cosmos.azure.us' : 'gremlin.cosmos.azure.com'

var privateEndpointConfigs = [
  {
    groupId: 'Gremlin'
    dnsZoneId: gremlinPrivateDnsZoneId
  }
  {
    groupId: 'Sql'
    dnsZoneId: sqlPrivateDnsZoneId
  }
]

var baseLogCategories = [
  'GremlinRequests'
  'ControlPlaneRequests'
  'PartitionKeyRUConsumption'
  'PartitionKeyStatistics'
]

var logCategories = logDataPlaneRequests ? concat(baseLogCategories, [ 'DataPlaneRequests' ]) : baseLogCategories

// ---------- Cosmos DB account ----------

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      {
        name: 'EnableGremlin'
      }
    ]
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: zoneRedundant
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }

    // Network: private endpoints only
    publicNetworkAccess: 'Disabled'
    isVirtualNetworkFilterEnabled: false
    ipRules: []
    networkAclBypass: 'None'
    networkAclBypassResourceIds: []

    // Auth: Gremlin requires keys. Block key-based schema changes.
    disableLocalAuth: false
    disableKeyBasedMetadataWriteAccess: true

    minimalTlsVersion: 'Tls12'
    enableAutomaticFailover: false
    enableFreeTier: false

    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 720
        backupStorageRedundancy: 'Geo'
      }
    }

    diagnosticLogSettings: {
      enableFullTextQuery: enableFullTextQuery ? 'True' : 'False'
    }
  }
}

// ---------- Database and graph ----------

resource gremlinDb 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases@2024-11-15' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource graph 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs@2024-11-15' = {
  parent: gremlinDb
  name: graphName
  properties: {
    resource: {
      id: graphName
      partitionKey: {
        paths: [
          partitionKeyPath
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
    options: {
      autoscaleSettings: {
        maxThroughput: maxAutoscaleThroughput
      }
    }
  }
}

// ---------- Private endpoints (serialized: Cosmos rejects concurrent PE operations) ----------

@batchSize(1)
resource privateEndpoints 'Microsoft.Network/privateEndpoints@2023-11-01' = [for cfg in privateEndpointConfigs: {
  name: 'pe-${accountName}-${toLower(cfg.groupId)}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${accountName}-${toLower(cfg.groupId)}'
        properties: {
          privateLinkServiceId: account.id
          groupIds: [
            cfg.groupId
          ]
        }
      }
    ]
  }
}]

// Remove this block if Azure Policy (DeployIfNotExists) manages private DNS zone groups
resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = [for (cfg, i) in privateEndpointConfigs: {
  parent: privateEndpoints[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cfg-${toLower(cfg.groupId)}'
        properties: {
          privateDnsZoneId: cfg.dnsZoneId
        }
      }
    ]
  }
}]

// ---------- Diagnostic settings to Sentinel workspace ----------

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-sentinel'
  scope: account
  properties: {
    workspaceId: sentinelWorkspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [for category in logCategories: {
      category: category
      enabled: true
    }]
  }
}

// ---------- Primary key into Key Vault (never emitted as output) ----------

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource keySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: '${accountName}-primary-key'
  properties: {
    value: account.listKeys().primaryMasterKey
    contentType: 'Cosmos DB Gremlin primary key'
  }
}

// ---------- Outputs (no secrets) ----------

output accountId string = account.id
output gremlinEndpoint string = 'wss://${accountName}.${gremlinSuffix}:443/'
output documentEndpoint string = account.properties.documentEndpoint
output gremlinResourcePath string = '/dbs/${databaseName}/colls/${graphName}'
output keyVaultSecretName string = keySecret.name
