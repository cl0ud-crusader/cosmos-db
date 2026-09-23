// Prerequisites for main.bicep: private endpoint subnet, private DNS zones, VNet links.
// Deploy into the resource group that holds the existing virtual network.
targetScope = 'resourceGroup'

@description('Name of the existing virtual network (must be in this resource group).')
param vnetName string

@description('Name of the new subnet for private endpoints.')
param subnetName string = 'snet-privateendpoints'

@description('Address prefix for the new subnet. Must fit inside the VNet address space and not overlap existing subnets. /27 recommended.')
param subnetPrefix string

@description('Optional resource ID of an NSG to attach. Leave empty for none. Many CMMC baselines deny subnets without an NSG.')
param nsgId string = ''

@description('Extra VNet resource IDs to link to the zones, such as the hub VNet hosting your DNS resolver or forwarders.')
param additionalVnetIds array = []

param tags object = {}

// ---------- Variables ----------

var isGov = environment().name == 'AzureUSGovernment'

var zoneNames = [
  isGov ? 'privatelink.gremlin.cosmos.azure.us' : 'privatelink.gremlin.cosmos.azure.com'
  isGov ? 'privatelink.documents.azure.us' : 'privatelink.documents.azure.com'
]

var allVnetIds = union([ resourceId('Microsoft.Network/virtualNetworks', vnetName) ], additionalVnetIds)

// Every zone x every VNet
var links = flatten(map(range(0, length(zoneNames)), zi => map(allVnetIds, v => {
  zoneIndex: zi
  vnetId: v
  linkName: 'link-${last(split(v, '/'))}'
})))

// ---------- Subnet ----------

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: vnetName
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetPrefix
    // Enabled = NSG rules and UDRs apply to private endpoint traffic
    privateEndpointNetworkPolicies: 'Enabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    networkSecurityGroup: empty(nsgId) ? null : {
      id: nsgId
    }
  }
}

// ---------- Private DNS zones ----------

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in zoneNames: {
  name: z
  location: 'global'
  tags: tags
}]

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for l in links: {
  parent: zones[l.zoneIndex]
  name: l.linkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: l.vnetId
    }
  }
}]

// ---------- Outputs: paste into main.bicepparam ----------

output privateEndpointSubnetId string = peSubnet.id
output gremlinPrivateDnsZoneId string = zones[0].id
output sqlPrivateDnsZoneId string = zones[1].id
