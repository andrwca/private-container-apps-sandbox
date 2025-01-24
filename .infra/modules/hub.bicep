import { uniqueResourceName } from '../functions/naming.bicep'

param location string
param environment string
param appName string

@description('The address space for the virtual network for the hub. Should be in CIDR format.')
param addressRange string

@description('The spoke\'s address spaces. These will be used to create the gateway subnet route table.')
param spokes spoke[]

@description('The address space for the VPN client devices. Should be in CIDR format.')
param vpnClientAddressRange string

@description('Defines a spoke.')
type spoke = {
  name: string
  addressRange: string
}

// Set the VPN Gateway SKU. This can be changed to a higher SKU if needed.
var vpnGatewaySku = 'VpnGw1' 

// App Id for the Azure VPN enterprise application (doesn't change)
var azureVpnAppId = '41b23e61-6c1e-4545-b367-cd054e0ed4b4'

// Address spaces for subnet and VPN.
var gatewayAddressSpace = cidrSubnet(addressRange, 24, 0)
var dnsResolverAddressSpace = cidrSubnet(addressRange, 24, 1)
var firewallAddressSpace = cidrSubnet(addressRange, 26, 9)
var vpnClientAddressSpace = cidrSubnet(vpnClientAddressRange, 24, 0)

// Inbound IP for the DNS resolver
var dnsResolverInboundIp = cidrHost(dnsResolverAddressSpace, 3)

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: uniqueResourceName('vnet', appName, environment)
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressRange]
    }
    dhcpOptions: {
      dnsServers: [
        dnsResolverInboundIp
      ]
    }
  }
}

// Add a route table to foward spoke addresses to the firewall.
resource hubRouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: uniqueResourceName('rt', 'firewall-hub-${appName}', environment)
  location: location
  properties: {
    routes: [
      for spoke in spokes: {
        name: 'route-${spoke.name}'
        properties: {
          addressPrefix: spoke.addressRange
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.outputs.firewallPrivateIpAddress
        }
      }
    ]
  }
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'GatewaySubnet'
  parent: vnet
  properties: {
    // Network security groups cannot be associated with a gateway subnet
    addressPrefix: gatewayAddressSpace
    routeTable: {
      id: hubRouteTable.id
    }
  }
}

resource dnsResolverSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'dns-resolver-subnet'
  parent: vnet
  properties: {
    addressPrefix: dnsResolverAddressSpace
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    delegations: [
      {
        name: 'Microsoft.Network.dnsResolvers'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = { 
  name: 'AzureFirewallSubnet'
  parent: vnet
  properties: {
    // Network security groups cannot be associated with the firewall subnet
    addressPrefix: firewallAddressSpace
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: uniqueResourceName('nsg', appName, environment)
  location: location
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: uniqueResourceName('pip', 'gateway-${appName}', environment)
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: uniqueResourceName('vng', appName, environment)
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'vnet-gateway-config'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: gatewaySubnet.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    activeActive: false
    sku: {
      name: vpnGatewaySku
      tier: vpnGatewaySku
    }
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          // Address space for vpn client devices. Must not overlap with the hub address space or any spoke networks.
          vpnClientAddressSpace
        ]
      }
      vpnClientProtocols: [
        'OpenVPN'
      ]
      vpnAuthenticationTypes: [
        'AAD'
      ]
      aadTenant: '${az.environment().authentication.loginEndpoint}${subscription().tenantId}'
      aadIssuer: 'https://sts.windows.net/${subscription().tenantId}/'
      aadAudience: azureVpnAppId
    }
  }
}

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: uniqueResourceName('dr', appName, environment)
  location: location
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource resolverInboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: resolver
  name: 'hub-inbound'
  location: location
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Static'
        privateIpAddress: dnsResolverInboundIp
        subnet: {
          id: dnsResolverSubnet.id
        }
      }
    ]
  }
}

// Single private DNS zone for container apps
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.uksouth.azurecontainerapps.io'
  location: 'global'
}

// Allows the dns names in the private DNS zone to be resolvable via the default VNET DNS settings.
resource hubVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'hub-vnet-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

module firewall './firewall.bicep' = {
  name: 'firewall'
  params: {
    location: location
    appName: appName
    environment: environment
    subnetId: firewallSubnet.id
  }
}

output vnet object = {
  id: vnet.id
  name: vnet.name
}

output privateDnsZone object = {
  containerApps: {
    id: privateDnsZone.id
    name: privateDnsZone.name
  }
}

output firewallPrivateIpAddress string = firewall.outputs.firewallPrivateIpAddress
output dnsResolverInboundIpAddress string = dnsResolverInboundIp
