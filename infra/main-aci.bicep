// main-aci.bicep for Addok on Azure Container Instances
// This file provisions Azure Container Instances (ACI) for the Addok stack using Container Groups
// - Container Group for addok
// - Container Group for addok-redis
// - Storage Account for Azure File Share
// - Log Analytics Workspace
// - Application Insights

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

param location string
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


// Container Group: addok + addok-redis
resource addokStackAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: '${resourceToken}-addokstack'
  location: location
  properties: {
    containers: [
      {
        name: 'addok'
        properties: {
          image: 'etalab/addok'
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 4
            }
          }
          ports: [
            {
              port: 7878
            }
          ]
          environmentVariables: [
            { name: 'WORKERS', value: string(WORKERS) }
            { name: 'WORKER_TIMEOUT', value: string(WORKER_TIMEOUT) }
            { name: 'LOG_QUERIES', value: string(LOG_QUERIES) }
            { name: 'LOG_NOT_FOUND', value: string(LOG_NOT_FOUND) }
            { name: 'SLOW_QUERIES', value: string(SLOW_QUERIES) }
            { name: 'BENOIT_REDIS_HOST', value: 'localhost' }
          ]
          volumeMounts: [
            {
              name: 'share-volume'
              mountPath: '/data'
              readOnly: false
            }
            {
              name: 'logs-volume'
              mountPath: '/logs'
              readOnly: false
            }
          ]
        }
      }
      {
        name: 'addok-redis'
        properties: {
          image: 'etalab/addok-redis'
          resources: {
            requests: {
              cpu: 2
              memoryInGB: 4
            }
          }
          ports: [
            {
              port: 6379
            }
          ]
          volumeMounts: [
            {
              name: 'share-volume'
              mountPath: '/data'
              readOnly: false
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          protocol: 'TCP'
          port: 7878
        }
        {
          protocol: 'TCP'
          port: 6379
        }
      ]
    }
    volumes: [
      {
        name: 'share-volume'
        azureFile: {
          shareName: 'addokfileshare'
          storageAccountName: addokData.name
          storageAccountKey: addokData.listKeys().keys[0].value
        }
      }
      {
        name: 'logs-volume'
        azureFile: {
          shareName: 'addoklogfileshare'
          storageAccountName: addokData.name
          storageAccountKey: addokData.listKeys().keys[0].value
        }
      }
    ]
    diagnostics: {
      logAnalytics: {
        workspaceId: logAnalytics.properties.customerId
        workspaceKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

output addokAciFqdn string = addokStackAci.properties.ipAddress.fqdn
