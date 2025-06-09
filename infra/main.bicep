// main.bicep for Addok on Azure Container Apps
// This file provisions all required Azure resources for the Addok stack
// - Container Apps Environment
// - Container Apps (addok, addok-redis)
// - Storage Accounts (addok-data, logs)
// - Azure Container Registry
// - Key Vault
// - Log Analytics Workspace
// - Application Insights
@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

param location string
// param resourceGroupName string // Not used, removed to fix lint error
param WORKERS int
param WORKER_TIMEOUT int
param LOG_QUERIES int
param LOG_NOT_FOUND int
param SLOW_QUERIES int

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${resourceToken}-log'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourceToken}-appi'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Container Apps Environment
resource containerEnv 'Microsoft.App/managedEnvironments@2025-02-02-preview' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'appProfile'
        workloadProfileType: 'D4'
        minimumCount: 1
        maximumCount: 2
      }
    ]
  }
  resource addokfileshare 'storages@2025-02-02-preview' = {
    name: 'addokfileshare'
    properties: {
      azureFile: {
        accountName: addokData.name
        accountKey: addokData.listKeys().keys[0].value
        accessMode: 'ReadOnly'
        shareName: 'addokfileshare'
      }
    }
  }

  resource addoklogfileshare 'storages@2025-02-02-preview' = {
    name: 'addoklogfileshare'
    properties: {
      azureFile: {
        accountName: addokData.name
        accountKey: addokData.listKeys().keys[0].value
        accessMode: 'ReadWrite'
        shareName: 'addoklogfileshare'
      }
    }
  }
}


// Storage Account for addok-data
resource addokData 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: toLower('${resourceToken}data')
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    largeFileSharesState: 'Enabled'
  }
}

// Azure File Share for Addok DB and config
resource addokFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${addokData.name}/default/addokfileshare'
  properties: {
    enabledProtocols: 'SMB'
    shareQuota: 10 // 10 GiB, adjust as needed
    accessTier: 'Hot'
  }
}

resource addokLogFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: '${addokData.name}/default/addoklogfileshare'
  properties: {
    enabledProtocols: 'SMB'
    shareQuota: 10 // 10 GiB, adjust as needed
    accessTier: 'Hot'
  }
}



// Container App: addok
resource addokApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'addokapp'
  location: location
  properties: {
    managedEnvironmentId: containerEnv.id
    workloadProfileName: 'appProfile'
    configuration: {
      ingress: {
        external: true
        targetPort: 7878
      }
    }
    template: {
      containers: [
        {
          name: 'addok'
          image: 'etalab/addok'
          env: [
            { name: 'WORKERS', value: string(WORKERS) }
            { name: 'WORKER_TIMEOUT', value: string(WORKER_TIMEOUT) }
            { name: 'LOG_QUERIES', value: string(LOG_QUERIES)}
            { name: 'LOG_NOT_FOUND', value: string(LOG_NOT_FOUND) }
            { name: 'SLOW_QUERIES', value: string(SLOW_QUERIES) }
            { name: 'REDIS_HOST', value: 'localhost' }
            { name: 'REDIS_PORT', value: '6379' }
    
          ]
          resources: {
            cpu: 1
            memory: '2.0Gi'
          }
          probes: [
            {
              type: 'Startup'
              periodSeconds: 5
              timeoutSeconds: 5
              successThreshold: 1
              failureThreshold: 20
              tcpSocket: {
                port: 7878
              }
            }
            {
              type: 'Liveness'
              periodSeconds: 5
              timeoutSeconds: 5
              successThreshold: 1
              failureThreshold: 10
              tcpSocket: {
                port: 7878
              }
            }
            {
              type: 'Readiness'
              periodSeconds: 5
              timeoutSeconds: 5
              successThreshold: 1
              failureThreshold: 10
              tcpSocket: {
                port: 7878
              }
            }
          ]
          volumeMounts: [
            {
              volumeName: 'share-volume'
              mountPath: '/data'
              subPath: 'data'
            }
            {
              volumeName: 'share-volume'
              mountPath: '/etc/addok'
              subPath: 'addok'
            }
            {
              volumeName: 'logs-volume'
              mountPath: '/logs'
            }
          ]
        }
        {
          name: 'addok-redis'
          image: 'etalab/addok-redis'
          resources: {
            cpu: 2
            memory: '6.0Gi'
          }
         
          probes: [
            {
              type: 'Startup'
              periodSeconds: 30
              timeoutSeconds: 240
              successThreshold: 1
              failureThreshold: 20
              tcpSocket: {
                port: 6379
              }
            }
            {
              type: 'Liveness'
              periodSeconds: 30
              timeoutSeconds: 240
              successThreshold: 1
              failureThreshold: 10
              tcpSocket: {
                port: 6379
              }
            }
            {
              type: 'Readiness'
              periodSeconds: 30
              timeoutSeconds: 240
              successThreshold: 1
              failureThreshold: 10
              tcpSocket: {
                port: 6379
              }
            }
          ]
          volumeMounts: [
            {
              volumeName: 'share-volume'
              mountPath: '/data'
              subPath: 'redis'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'share-volume'
          storageType: 'AzureFile'
          storageName: 'addokfileshare'
        }
        {
          name: 'logs-volume'
          storageType: 'AzureFile'
          storageName: 'addoklogfileshare'
        }
      ]
    }
  }
  dependsOn: [
    containerEnv::addoklogfileshare
    containerEnv::addokfileshare
  ]
}



output ADDOK_FQDN string = addokApp.properties.configuration.ingress.fqdn
output STORAGE_ACCOUNT_NAME string = addokData.name
