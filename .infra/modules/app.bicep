import { uniqueResourceName } from '../functions/naming.bicep'

param location string
param appName string
param environment string

@description('The address space for the virtual network for the app. Should be in CIDR format.')
param addressSpace string

@description('The private DNS zone collection that the app can make use of.')
param privateDnsZones privateDnsZoneCollection

@description('The private IP address of the firewall.')
param firewallPrivateIpAddress string

@description('Defines a collection of private DNS zone IDs.')
type privateDnsZoneCollection = {
  containerApps: {
    id: string
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: uniqueResourceName('vn', appName, environment)
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressSpace]
    }
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: uniqueResourceName('nsg', appName, environment)
  location: location
}

// A default route table to route all traffic through the firewall. Can be used by workload subnets.
resource routeTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: uniqueResourceName('rt-firewall-default', appName, environment)
  location: location
  properties: {
    routes: [
      {
        name: 'default-route'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIpAddress
        }
      }
    ]
  }
}

resource subnetContainerAppEnvironment 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'subnet-container-app-environment'
  parent: vnet
  properties: {
    addressPrefix: cidrSubnet(addressSpace, 23, 0)
    routeTable: {
      id: routeTable.id
    }
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    delegations: [
      {
        name: 'delegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

resource subnetPrivateEndpoint 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: 'subnet-pe'
  parent: vnet
  properties: {
    addressPrefix: cidrSubnet(addressSpace, 23, 1)
    routeTable: {
      id: routeTable.id
    }
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: uniqueResourceName('cae', appName, environment)
  location: location
  properties: {
    vnetConfiguration: {
      infrastructureSubnetId: subnetContainerAppEnvironment.id
      internal: true
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: uniqueResourceName('law', appName, environment)
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: uniqueResourceName('ca', appName, environment)
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 80
        transport: 'HTTP'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template:{
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      containers:[
        {
          name: 'hello-world'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

// Creates a private endpoint for the container app environment
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: uniqueResourceName('pe', appName, environment)
  location: location
  properties: {
    subnet: {
      id: subnetPrivateEndpoint.id
    }
    privateLinkServiceConnections: [
      {
        name: 'container-apps-connection'
        properties: {
          privateLinkServiceId: containerAppEnvironment.id
          groupIds: ['managedEnvironments']
        }
      }
    ]
  }
}

// Links the private endpoint to the private DNS zone. This automatically adds the correct DNS records to the private DNS zone.
resource privateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'pe-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'pe-dns-zone-config'
        properties: {
          privateDnsZoneId: privateDnsZones.containerApps.id
        }
      }
    ]
  }
}

output vnet object = {
  id: vnet.id
  name: vnet.name
}
