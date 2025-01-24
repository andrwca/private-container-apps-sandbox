targetScope = 'subscription'

import {resourceName} from './functions/naming.bicep'

param location string = 'uksouth'
param environment string = 'dev'
param hubAddressRange string = '10.0.0.0/16'
param hubVpnClientAddressRange string = '10.10.0.0/16'
param app1AddressRange string = '10.1.0.0/16'
param app2AddressRange string = '10.2.0.0/16'

resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceName('rg', 'hub', environment)
  location: location
}

resource app1ResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceName('rg', 'app1', environment)
  location: location
}

resource app2ResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceName('rg', 'app2', environment)
  location: location
}

module hubModule './modules/hub.bicep' = {
  name: 'hub'
  scope: hubResourceGroup
  params: {
    appName: 'hub'
    location: location
    environment: environment
    addressRange: hubAddressRange
    spokes: [ 
      {
        name: 'app1'
        addressRange: app1AddressRange
      }
      {
        name: 'app2'
        addressRange: app2AddressRange
      }
    ]
    vpnClientAddressRange: hubVpnClientAddressRange
  }
}

module app1 './modules/app.bicep' = {
  name: 'app1'
  scope: app1ResourceGroup
  params: {
    appName: 'app1'
    location: location
    environment: environment
    addressSpace: app1AddressRange
    firewallPrivateIpAddress: hubModule.outputs.firewallPrivateIpAddress
    dnsResolverInboundIpAddress: hubModule.outputs.dnsResolverInboundIpAddress
    privateDnsZones: {
      containerApps: {
        id: hubModule.outputs.privateDnsZone.containerApps.id
      }
    }
  }
}

module app2 './modules/app.bicep' = {
  name: 'app2'
  scope: app2ResourceGroup
  params: {
    appName: 'app2'
    location: location
    environment: environment
    addressSpace: app2AddressRange
    firewallPrivateIpAddress: hubModule.outputs.firewallPrivateIpAddress
    dnsResolverInboundIpAddress: hubModule.outputs.dnsResolverInboundIpAddress
    privateDnsZones: {
      containerApps: {
        id: hubModule.outputs.privateDnsZone.containerApps.id
      }
    }
  }
}

module peeringHubToApp1 './modules/peering.bicep' = {
  name: 'peering-hub-to-app1'
  scope: hubResourceGroup
  params: {
    sourceDisplayName: 'Hub'
    sourceName: hubModule.outputs.vnet.name
    destinationDisplayName: 'App1'
    destinationVNetId: app1.outputs.vnet.id
    allowGatewayTransit: true
  }
}

module peeringHubToApp2 './modules/peering.bicep' = {
  name: 'peering-hub-to-app2'
  scope: hubResourceGroup
  params: {
    sourceDisplayName: 'Hub'
    sourceName: hubModule.outputs.vnet.name
    destinationDisplayName: 'App2'
    destinationVNetId: app2.outputs.vnet.id
    allowGatewayTransit: true
  }
}

module peeringApp1ToHub './modules/peering.bicep' = {
  name: 'peering-app1-to-hub'
  scope: app1ResourceGroup
  params: {
    sourceDisplayName: 'App1'
    sourceName: app1.outputs.vnet.name
    destinationDisplayName: 'Hub'
    destinationVNetId: hubModule.outputs.vnet.id
    useRemoteGateways: true
  }
}

module peeringApp2ToHub './modules/peering.bicep' = {
  name: 'peering-app2-to-hub'
  scope: app2ResourceGroup
  params: {
    sourceDisplayName: 'App2'
    sourceName: app2.outputs.vnet.name
    destinationDisplayName: 'Hub'
    destinationVNetId: hubModule.outputs.vnet.id
    useRemoteGateways: true
  }
}
