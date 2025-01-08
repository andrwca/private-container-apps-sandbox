
@description('The name of the source vnet.')
param sourceDisplayName string

@description('The name of the source vnet.')
param sourceName string

@description('The name of the destination vnet.')
param destinationDisplayName string

@description('The id of the destination vnet.')
param destinationVNetId string

@description('Allow gateway transit.')
param allowGatewayTransit bool = false

@description('Use remote gateways.')
param useRemoteGateways bool = false

resource sourceVNet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: sourceName
}

resource hubToAppPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  name: '${sourceDisplayName}To${destinationDisplayName}Peering'
  parent: sourceVNet
  properties: {
    allowVirtualNetworkAccess: true
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: {
      id: destinationVNetId
    }
  }
}
