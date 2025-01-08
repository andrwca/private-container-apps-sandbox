import { uniqueResourceName } from '../functions/naming.bicep'

param location string
param appName string
param environment string
param subnetId string

// See: https://learn.microsoft.com/en-us/azure/firewall-manager/secure-hybrid-network

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: uniqueResourceName('pip-firewall', appName, environment)
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Log analytics for the firewall policy.
resource policyLogAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: uniqueResourceName('law-firewall-policy', appName, environment)
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Policy linked to the firewall rules.
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01'= {
  name: uniqueResourceName('fw-policy', appName, environment)
  location: location
  properties: {
    insights: {
      isEnabled: true 
      retentionDays: 7
      logAnalyticsResources: {
        defaultWorkspaceId: {
          id: policyLogAnalytics.id
        }
        workspaces: [
          {
            region: location
            workspaceId: {
              id: policyLogAnalytics.id
            }
          }
        ]
      }
    }
    threatIntelMode: 'Alert'
  }
}

// This shouldn't be so permissive, just for testing.
resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  name: 'DefaultNetworkRuleCollectionGroup'
  parent: firewallPolicy
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'global-rule-allow-https'
        priority: 1000
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'allow-https'
            ipProtocols: [
              'TCP'
            ]
            destinationAddresses: [
              '*'
            ]
            sourceAddresses: [
              '*'
            ]
            destinationPorts: [
              '443'
            ]
          }
        ]
      }
    ]
  }
}

// The firewall it's self.
resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: uniqueResourceName('fw', appName, environment)
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: {
      id: firewallPolicy.id
    }
    ipConfigurations: [
      {
        name: 'firewall-ip-config'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

output firewallPrivateIpAddress string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
