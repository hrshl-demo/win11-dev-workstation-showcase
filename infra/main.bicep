targetScope = 'subscription'

@description('The azd environment name. Resource names use a deterministic hash, not personal data.')
@minLength(1)
@maxLength(64)
param environmentName string

@description('An Azure region selected by the developer and approved by IT.')
@minLength(1)
param location string

@description('An actual, already-published EMI application image, preferably qualified by sha256 digest. There is deliberately no demo/placeholder image default.')
@minLength(1)
param containerImage string

var suffix = take(uniqueString(subscription().id, environmentName, location), 10)
var tags = {
  'azd-env-name': environmentName
  'showcase': 'synthetic-data-only'
}

resource group 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-workstation-${suffix}'
  location: location
  tags: tags
}

// Published AVM+azd patterns are used for the hosting stack and application.
module logs 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'showcase-logs'
  scope: group
  params: {
    name: 'log-${suffix}'
    location: location
    tags: tags
    dataRetention: 30
    dailyQuotaGb: '1'
    forceCmkForQuery: false
    enableTelemetry: false
  }
}

module stack 'br/public:avm/ptn/azd/container-apps-stack:0.4.0' = {
  name: 'showcase-container-stack'
  scope: group
  params: {
    containerAppsEnvironmentName: 'cae-${suffix}'
    containerRegistryName: 'cr${suffix}'
    logAnalyticsWorkspaceName: logs.outputs.name
    location: location
    tags: tags
    acrAdminUserEnabled: false
    acrSku: 'Basic'
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
    enableTelemetry: false
  }
}

module identity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'showcase-managed-identity'
  scope: group
  params: {
    name: 'id-emi-${suffix}'
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module vault 'br/public:avm/res/key-vault/vault:0.14.2' = {
  name: 'showcase-key-vault'
  scope: group
  params: {
    name: 'kv-emi-${suffix}'
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    enableVaultForDeployment: false
    enableVaultForTemplateDeployment: false
    enableVaultForDiskEncryption: false
    // The sample needs no secret. IT must approve private networking before future secret use.
    publicNetworkAccess: 'Disabled'
    roleAssignments: [
      {
        roleDefinitionIdOrName: '4633458b-17de-408a-b874-0445c86b69e6'
        principalId: identity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
    diagnosticSettings: [
      {
        name: 'vault-audit'
        workspaceResourceId: logs.outputs.resourceId
      }
    ]
    enableTelemetry: false
  }
}

module emi 'br/public:avm/ptn/azd/acr-container-app:0.5.0' = {
  name: 'showcase-emi-api'
  scope: group
  params: {
    name: 'ca-emi-${suffix}'
    containerAppsEnvironmentName: stack.outputs.environmentName
    containerRegistryName: stack.outputs.registryName
    identityName: identity.outputs.name
    identityType: 'UserAssigned'
    userAssignedIdentityResourceId: identity.outputs.resourceId
    principalId: identity.outputs.principalId
    imageName: containerImage
    location: location
    tags: union(tags, { 'azd-service-name': 'emi' })
    targetPort: 8080
    ingressEnabled: true
    external: true
    ingressAllowInsecure: false
    containerCpuCoreCount: '0.5'
    containerMemory: '1Gi'
    containerMinReplicas: 0
    containerMaxReplicas: 1
    env: [
      {
        name: 'PORT'
        value: '8080'
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: identity.outputs.clientId
      }
      {
        name: 'KEY_VAULT_URI'
        value: vault.outputs.uri
      }
    ]
    containerProbes: [
      {
        type: 'Readiness'
        httpGet: {
          path: '/health'
          port: 8080
        }
        initialDelaySeconds: 5
        periodSeconds: 5
        timeoutSeconds: 2
        failureThreshold: 3
      }
      {
        type: 'Liveness'
        httpGet: {
          path: '/health'
          port: 8080
        }
        initialDelaySeconds: 10
        periodSeconds: 10
        timeoutSeconds: 2
        failureThreshold: 3
      }
    ]
    enableTelemetry: false
  }
}

output AZURE_RESOURCE_GROUP string = group.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = stack.outputs.registryLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = stack.outputs.registryName
output AZURE_CONTAINER_APPS_ENVIRONMENT_ID string = stack.outputs.environmentResourceId
output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = logs.outputs.resourceId
output AZURE_KEY_VAULT_NAME string = vault.outputs.name
output AZURE_KEY_VAULT_URI string = vault.outputs.uri
output AZURE_CLIENT_ID string = identity.outputs.clientId
output API_URL string = emi.outputs.uri
