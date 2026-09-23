using './network-prereqs.bicep'

// Replace every <...> value before deploying.

param vnetName = '<existing-vnet-name>'
param subnetName = 'snet-privateendpoints'
param subnetPrefix = '<10.x.y.0/27>'

// Optional: '/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/networkSecurityGroups/<nsg>'
param nsgId = ''

// Optional: hub VNet where DNS resolver or forwarders live
param additionalVnetIds = []

param tags = {
  environment: 'prod'
  compliance: 'cmmc-l2'
}
