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
param ACR_NAME string
param ACR_ADDOK_IMPORTER_IMAGE_TAG string = 'latest' // Default tag for the Addok importer image in ACR
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
  name: 'addok-${environmentName}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${addocAcrPull.id}': {}
    }
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
  resource addokfileshare 'storages@2025-02-02-preview' = {
    name: 'addokfileshare'
    properties: {
      azureFile: {
        accountName: addokData.name
        accountKey: addokData.listKeys().keys[0].value
        accessMode: 'ReadWrite'
        shareName: addokData::fileService::addokFileShare.name
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
        shareName: addokData::fileService::addokLogFileShare.name
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

  resource queueServices 'queueServices' = {
    resource queue 'queues' = {
      name: 'addok-events'
      properties: {}
    }
    name: 'default'
  }

  // Nested file service for Addok DB and config
  resource fileService 'fileServices@2023-05-01' = {
    name: 'default'

    resource addokFileShare 'shares@2023-05-01' = {
      name: 'addokfileshare'
      properties: {
        enabledProtocols: 'SMB'
        shareQuota: 10 // 10 GiB, adjust as needed
        accessTier: 'Hot'
      }
    }

    // Nested file share for Addok logs
    resource addokLogFileShare 'shares@2023-05-01' = {
      name: 'addoklogfileshare'
      properties: {
        enabledProtocols: 'SMB'
        shareQuota: 10 // 10 GiB, adjust as needed
        accessTier: 'Hot'
      }
    }
  }
}
resource addokRegistry 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = {
  name: ACR_NAME
}

/* resource addokRegistry2 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: 'addok${resourceToken}reg'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
} */

resource addocAcrPull 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'addock-acr-pull'
  location: location
}

@description('This allows the managed identity of the container app to access the registry, note scope is applied to the wider ResourceGroup not the ACR')
resource uaiRbacAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, addocAcrPull.id, 'ACR Pull Role RG')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: addocAcrPull.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource addokApp 'Microsoft.App/containerApps@2025-02-02-preview' = {
  name: 'addokapp'
  location: location
  tags: { 'azd-service-name-not-used': 'addok-importer' }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 7878
        additionalPortMappings: [
          {
            targetPort: 8000
            external: false
            exposedPort: 8000
          }
        ]
      }
      registries: [
        {
          server: addokRegistry.properties.loginServer
          identity: addocAcrPull.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'addok'
          image: '${addokRegistry.properties.loginServer}/etalab/addok'
          env: [
            { name: 'WORKERS', value: string(WORKERS) }
            { name: 'WORKER_TIMEOUT', value: string(WORKER_TIMEOUT) }
            { name: 'LOG_QUERIES', value: string(LOG_QUERIES) }
            { name: 'LOG_NOT_FOUND', value: string(LOG_NOT_FOUND) }
            { name: 'SLOW_QUERIES', value: string(SLOW_QUERIES) }
            { name: 'REDIS_HOST', value: addokRedisApp.name }
            { name: 'REDIS_PORT', value: '6379' }
            { name: 'SQLITE_DB_PATH', value: '/localdata/my_addok.db' }
            { name: 'ADDOK_CONFIG_PATH', value: '/etc/addok/addok.cfg' }
            { name: 'ADDOK_LOG_PATH', value: '/logs/addok.log' }
            { name: 'RESTART', value: '2' }
          ]

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
              mountPath: '/daily'
              subPath: 'daily'
            }
            {
              volumeName: 'addok-data-volume'
              mountPath: '/localdata'
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
          name: 'addok-importer'
          image: '${addokRegistry.properties.loginServer}/etalab/addok-importer-aca:${ACR_ADDOK_IMPORTER_IMAGE_TAG}'

          env: [
            { name: 'WORKERS', value: string(WORKERS) }
            { name: 'WORKER_TIMEOUT', value: string(WORKER_TIMEOUT) }
            { name: 'LOG_QUERIES', value: string(LOG_QUERIES) }
            { name: 'LOG_NOT_FOUND', value: string(LOG_NOT_FOUND) }
            { name: 'SLOW_QUERIES', value: string(SLOW_QUERIES) }
            { name: 'REDIS_HOST', value: addokRedisApp.name }
            { name: 'REDIS_PORT', value: '6379' }
            { name: 'SQLITE_DB_PATH', value: '/localdata/my_addok.db' }
            { name: 'ADDOK_CONFIG_PATH', value: '/etc/addok/addok.cfg' }
            { name: 'ADDOK_LOG_PATH', value: '/logs/addok.log' }
            { name: 'TAG', value: ACR_ADDOK_IMPORTER_IMAGE_TAG }
          ]
          volumeMounts: [
            {
              volumeName: 'share-volume'
              mountPath: '/daily'
              subPath: 'daily'
            }
            {
              volumeName: 'addok-data-volume'
              mountPath: '/localdata'
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
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'addok-data-volume'
          storageType: 'EmptyDir'
        }
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

resource addokRedisApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'addokredisapp'
  location: location
  tags: { 'azd-service-name': 'addok-redis' }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: false
        targetPort: 6379
        transport: 'TCP'
      }
      registries: [
        {
          server: addokRegistry.properties.loginServer
          identity: addocAcrPull.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'addok-redis'
          image: '${addokRegistry.properties.loginServer}/etalab/addok-redis'
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
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    containerEnv::addoklogfileshare
    containerEnv::addokfileshare
  ]
}

resource ngnix 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ngnix'
  location: location
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      ingress: {
        external: false
        targetPort: 80
      }
    }
    template: {
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
      containers: [
        {
          name: 'ngnix'
          image: 'nginx'
        }
      ]
    }
  }
  dependsOn: [
    containerEnv::addoklogfileshare
    containerEnv::addokfileshare
  ]
}

resource importerJob 'Microsoft.App/jobs@2025-01-01' = {
  name: 'addokimporter'
  location: location
  properties: {
    environmentId: containerEnv.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 600 // 10 minutes
      scheduleTriggerConfig: {
        cronExpression: '*/2 * * * *'
        parallelism: 1
      }
    }
    template: {
      containers: [
        {
          name: 'importer'
          image: 'mcr.microsoft.com/azure-cli:latest'
          command: ['/bin/sh']
          args: [
            '-c'
            //'az login --identity --resource-id ${addokAppOperator.id} && az account show && az containerapp  exec --debug  --name ${addokApp.name} -g ${resourceGroup().name} --command /daily/m_addok_importer.sh'
            //'az login --identity --resource-id ${addokAppOperator.id} && az account show && script --return --quiet -c "az containerapp  exec --name ${addokApp.name} -g ${resourceGroup().name}   --command /daily/m_addok_importer.sh"  /dev/null'
            'echo "Addok import initialization...." && curl -X POST http://${addokApp.name}:8000/upload && echo "Addok import initialization completed."'
          ]
        }
      ]
    }
  }
  dependsOn: [
    containerEnv::addoklogfileshare
    containerEnv::addokfileshare
  ]
}

module systemTopic 'br/public:avm/res/event-grid/system-topic:0.6.2' = {
  name: 'systemTopicDeployment'
  params: {
    // Required parameters
    name: 'azrambi-event-grid-topic'
    source: addokData.id
    topicType: 'Microsoft.Storage.StorageAccounts'
    // Non-required parameters
    location: location
    eventSubscriptions: [
      {
        destination: {
          endpointType: 'StorageQueue'
          properties: {
            queueMessageTimeToLiveInSeconds: 86400
            resourceId: addokData.id
            queueName: addokData::queueServices::queue.name
          }
        }
        eventDeliverySchema: 'CloudEventSchemaV1_0'
        expirationTimeUtc: '2099-01-01T11:00:21.715Z'
        filter: {
          includedEventTypes: [
            'Microsoft.Storage.FileCreated'
            'Microsoft.Storage.FileDeleted'
            'Microsoft.Storage.FileRenamed'
          ]
          enableAdvancedFilteringOnArrays: true
          isSubjectCaseSensitive: false
        }
        name: 'addok-event-subscription'
        retryPolicy: {
          eventTimeToLive: '120'
          maxDeliveryAttempts: 10
        }
      }
    ]
  }
}

/*


// Event Grid System Topic for storage account events
resource storageEventGridTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: '${resourceToken}-storage-events'
  location: location
  properties: {
    source: addokData.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${addocAcrPull.id}': {}
    }
  }
  
  // Event subscription for blob created events
  resource fileCreatedSubscription 'eventSubscriptions@2022-06-15' = {
    name: 'file-created-events'
    properties: {
      destination: {
        endpointType: 'ServiceBusQueue'
        properties: {
          resourceId: addokData::queueServices::queue.id
        }
      }
      filter: {
        includedEventTypes: [
          'Microsoft.Storage.FileCreated'
          'Microsoft.Storage.FileDeleted'
          'Microsoft.Storage.FileRenamed'
        ]
        //subjectBeginsWith: '/fileServices/default/containers/uploads/'
        enableAdvancedFilteringOnArrays: false
        isSubjectCaseSensitive: false
      }
      eventDeliverySchema: 'EventGridSchema'
      retryPolicy: {
        maxDeliveryAttempts: 3
        eventTimeToLiveInMinutes: 1440 // 24 hours
      }
      deliveryWithResourceIdentity: {
        identity: {
          type: 'UserAssigned'
          userAssignedIdentity: addocAcrPull.id
        }
        destination: {
          endpointType: 'ServiceBusQueue'
          properties: {
            resourceId: addokData::queueServices::queue.id
          }
        }
      }
    }
  }
}
*/

output ADDOK_FQDN string = addokApp.properties.configuration.ingress.fqdn
output STORAGE_ACCOUNT_NAME string = addokData.name
output ACR_NAME string = addokRegistry.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = addokRegistry.properties.loginServer
