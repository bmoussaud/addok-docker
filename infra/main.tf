# main.tf for Addok on Azure Container Apps
# This file provisions all required Azure resources for the Addok stack
# - Container Apps Environment
# - Container Apps (addok, addok-redis)
# - Storage Accounts (addok-data, logs)
# - Azure Container Registry
# - Key Vault
# - Log Analytics Workspace
# - Application Insights

# Provider configuration
provider "azurerm" {
  features {}
}

# Data sources
data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Random string for unique resource naming
resource "random_string" "resource_token" {
  length  = 13
  special = false
  upper   = false
  numeric = true
}

# Local values
locals {
  resource_token = lower(random_string.resource_token.result)
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = "${local.resource_token}-log"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = var.environment_name
  }
}

# Application Insights
resource "azurerm_application_insights" "app_insights" {
  name                = "${local.resource_token}-appi"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.log_analytics.id
  application_type    = "web"

  tags = {
    Environment = var.environment_name
  }
}

# Storage Account for addok-data
resource "azurerm_storage_account" "addok_data" {
  name                          = "${local.resource_token}data"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  account_kind                  = "StorageV2"
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled    = true
  public_network_access_enabled = true
  large_file_share_enabled      = true

  tags = {
    Environment = var.environment_name
  }
}

# Storage Queue for events
resource "azurerm_storage_queue" "addok_events" {
  name                 = "addok-events"
  storage_account_name = azurerm_storage_account.addok_data.name
}

# File shares
resource "azurerm_storage_share" "addok_file_share" {
  name                 = "addokfileshare"
  storage_account_name = azurerm_storage_account.addok_data.name
  quota                = 10
  enabled_protocol     = "SMB"
  access_tier          = "Hot"
}

resource "azurerm_storage_share" "addok_log_file_share" {
  name                 = "addoklogfileshare"
  storage_account_name = azurerm_storage_account.addok_data.name
  quota                = 10
  enabled_protocol     = "SMB"
  access_tier          = "Hot"
}

# Reference to existing Container Registry
data "azurerm_container_registry" "addok_registry" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
}

# User-assigned Managed Identity for ACR Pull
resource "azurerm_user_assigned_identity" "addok_acr_pull" {
  name                = "addock-acr-pull"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = {
    Environment = var.environment_name
  }
}

# Role assignment for ACR Pull
resource "azurerm_role_assignment" "uai_rbac_acr_pull" {
  scope                = var.resource_group_id
  role_definition_id   = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
  principal_id         = azurerm_user_assigned_identity.addok_acr_pull.principal_id
  principal_type       = "ServicePrincipal"
}

# Container Apps Environment
resource "azurerm_container_app_environment" "container_env" {
  name                       = "addok-${var.environment_name}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics.id

  tags = {
    Environment = var.environment_name
  }

  depends_on = [azurerm_role_assignment.uai_rbac_acr_pull]
}

# Container Apps Environment Storage for addok file share
resource "azurerm_container_app_environment_storage" "addok_file_share_storage" {
  name                         = "addokfileshare"
  container_app_environment_id = azurerm_container_app_environment.container_env.id
  account_name                 = azurerm_storage_account.addok_data.name
  share_name                   = azurerm_storage_share.addok_file_share.name
  access_key                   = azurerm_storage_account.addok_data.primary_access_key
  access_mode                  = "ReadWrite"
}

# Container Apps Environment Storage for addok log file share
resource "azurerm_container_app_environment_storage" "addok_log_file_share_storage" {
  name                         = "addoklogfileshare"
  container_app_environment_id = azurerm_container_app_environment.container_env.id
  account_name                 = azurerm_storage_account.addok_data.name
  share_name                   = azurerm_storage_share.addok_log_file_share.name
  access_key                   = azurerm_storage_account.addok_data.primary_access_key
  access_mode                  = "ReadWrite"
}

# Addok Container App
resource "azurerm_container_app" "addok_app" {
  name                         = "addokapp"
  container_app_environment_id = azurerm_container_app_environment.container_env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.addok_acr_pull.id]
  }

  registry {
    server   = data.azurerm_container_registry.addok_registry.login_server
    identity = azurerm_user_assigned_identity.addok_acr_pull.id
  }

  ingress {
    external_enabled = true
    target_port      = 7878
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
    /*
    additional_port_mappings {
      target_port      = 8000
      external_enabled = false
      exposed_port     = 8000
    }*/
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "addok"
      image  = "${data.azurerm_container_registry.addok_registry.login_server}/etalab/addok"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "WORKERS"
        value = tostring(var.workers)
      }

      env {
        name  = "WORKER_TIMEOUT"
        value = tostring(var.worker_timeout)
      }

      env {
        name  = "LOG_QUERIES"
        value = tostring(var.log_queries)
      }

      env {
        name  = "LOG_NOT_FOUND"
        value = tostring(var.log_not_found)
      }

      env {
        name  = "SLOW_QUERIES"
        value = tostring(var.slow_queries)
      }

      env {
        name  = "REDIS_HOST"
        value = azurerm_container_app.addok_redis_app.name
      }

      env {
        name  = "REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "SQLITE_DB_PATH"
        value = "/localdata/my_addok.db"
      }

      env {
        name  = "ADDOK_CONFIG_PATH"
        value = "/etc/addok/addok.cfg"
      }

      env {
        name  = "ADDOK_LOG_PATH"
        value = "/logs/addok.log"
      }

      env {
        name  = "RESTART"
        value = "2"
      }

      startup_probe {
        transport                = "TCP"
        port                     = 7878
        interval_seconds         = 5
        timeout                  = 5
        failure_count_threshold  = 20
        
      }

      liveness_probe {
        transport                = "TCP"
        port                     = 7878
        interval_seconds         = 5
        timeout                  = 5
        failure_count_threshold  = 10
        
      }

      readiness_probe {
        transport                = "TCP"
        port                     = 7878
        interval_seconds         = 5
        timeout                  = 5
        failure_count_threshold  = 10
        
      }

      volume_mounts {
        name = "share-volume"
        path = "/daily"
      }

      volume_mounts {
        name = "addok-data-volume"
        path = "/localdata"
      }

      volume_mounts {
        name = "share-volume"
        path = "/etc/addok"
      }

      volume_mounts {
        name = "logs-volume"
        path = "/logs"
      }
    }

    container {
      name   = "addok-importer"
      image  = "${data.azurerm_container_registry.addok_registry.login_server}/etalab/addok-importer-aca:${var.acr_addok_importer_image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "WORKERS"
        value = tostring(var.workers)
      }

      env {
        name  = "WORKER_TIMEOUT"
        value = tostring(var.worker_timeout)
      }

      env {
        name  = "LOG_QUERIES"
        value = tostring(var.log_queries)
      }

      env {
        name  = "LOG_NOT_FOUND"
        value = tostring(var.log_not_found)
      }

      env {
        name  = "SLOW_QUERIES"
        value = tostring(var.slow_queries)
      }

      env {
        name  = "REDIS_HOST"
        value = azurerm_container_app.addok_redis_app.name
      }

      env {
        name  = "REDIS_PORT"
        value = "6379"
      }

      env {
        name  = "SQLITE_DB_PATH"
        value = "/localdata/my_addok.db"
      }

      env {
        name  = "ADDOK_CONFIG_PATH"
        value = "/etc/addok/addok.cfg"
      }

      env {
        name  = "ADDOK_LOG_PATH"
        value = "/logs/addok.log"
      }

      env {
        name  = "TAG"
        value = var.acr_addok_importer_image_tag
      }

      volume_mounts {
        name = "share-volume"
        path = "/daily"
      }

      volume_mounts {
        name = "addok-data-volume"
        path = "/localdata"
      }

      volume_mounts {
        name = "share-volume"
        path = "/etc/addok"
      }

      volume_mounts {
        name = "logs-volume"
        path = "/logs"
      }
    }

    volume {
      name         = "addok-data-volume"
      storage_type = "EmptyDir"
    }

    volume {
      name         = "share-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.addok_file_share_storage.name
    }

    volume {
      name         = "logs-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.addok_log_file_share_storage.name
    }
  }

  tags = {
    "azd-service-name-not-used" = "addok-importer"
    Environment                 = var.environment_name
  }

  depends_on = [
    azurerm_container_app_environment_storage.addok_file_share_storage,
    azurerm_container_app_environment_storage.addok_log_file_share_storage
  ]
}

# Redis Container App
resource "azurerm_container_app" "addok_redis_app" {
  name                         = "addokredisapp"
  container_app_environment_id = azurerm_container_app_environment.container_env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.addok_acr_pull.id]
  }

  registry {
    server   = data.azurerm_container_registry.addok_registry.login_server
    identity = azurerm_user_assigned_identity.addok_acr_pull.id
  }

  ingress {
    external_enabled = false
    target_port      = 6379
    transport        = "tcp"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "addok-redis"
      image  = "${data.azurerm_container_registry.addok_registry.login_server}/etalab/addok-redis"
      cpu    = 0.25
      memory = "0.5Gi"

      startup_probe {
        transport                = "TCP"
        port                     = 6379
        interval_seconds         = 30
        timeout                  = 240
        failure_count_threshold  = 20
      }

      liveness_probe {
        transport                = "TCP"
        port                     = 6379
        interval_seconds         = 30
        timeout                  = 240
        failure_count_threshold  = 10
      }

      readiness_probe {
        transport                = "TCP"
        port                     = 6379
        interval_seconds         = 30
        timeout                  = 240
        failure_count_threshold  = 10
      }
    }
  }

  tags = {
    "azd-service-name" = "addok-redis"
    Environment        = var.environment_name
  }

  depends_on = [
    azurerm_container_app_environment_storage.addok_file_share_storage,
    azurerm_container_app_environment_storage.addok_log_file_share_storage
  ]
}

# Nginx Container App
resource "azurerm_container_app" "nginx" {
  name                         = "nginx"
  container_app_environment_id = azurerm_container_app_environment.container_env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  ingress {
    external_enabled = false
    target_port      = 80

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "nginx"
      image  = "nginx"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  tags = {
    Environment = var.environment_name
  }

  depends_on = [
    azurerm_container_app_environment_storage.addok_file_share_storage,
    azurerm_container_app_environment_storage.addok_log_file_share_storage
  ]
}

# Container App Job for Importer
resource "azurerm_container_app_job" "importer_job" {
  name                         = "addokimporter"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.container_env.id

  replica_timeout_in_seconds = 600
  replica_retry_limit        = 1
  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "importer"
      image  = "mcr.microsoft.com/azure-cli:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      command = ["/bin/sh"]
      args = [
        "-c",
        "echo \"Addok import initialization....\" && curl -X POST http://${azurerm_container_app.addok_app.name}:8000/upload && echo \"Addok import initialization completed.\""
      ]
    }
  }

  tags = {
    Environment = var.environment_name
  }

  depends_on = [
    azurerm_container_app_environment_storage.addok_file_share_storage,
    azurerm_container_app_environment_storage.addok_log_file_share_storage
  ]
}

# Event Grid System Topic
resource "azurerm_eventgrid_system_topic" "storage_events" {
  name                   = "azrambi-event-grid-topic"
  location               = var.location
  resource_group_name    = var.resource_group_name
  source_arm_resource_id = azurerm_storage_account.addok_data.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  tags = {
    Environment = var.environment_name
  }
}

# Event Grid System Topic Event Subscription
resource "azurerm_eventgrid_system_topic_event_subscription" "addok_event_subscription" {
  name                = "addok-event-subscription"
  system_topic        = azurerm_eventgrid_system_topic.storage_events.name
  resource_group_name = var.resource_group_name

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.addok_data.id
    queue_name         = azurerm_storage_queue.addok_events.name
  }

  included_event_types = [
    "Microsoft.Storage.FileCreated",
    "Microsoft.Storage.FileDeleted",
    "Microsoft.Storage.FileRenamed"
  ]

  event_delivery_schema                = "CloudEventSchemaV1_0"
  expiration_time_utc                  = "2099-01-01T11:00:21.715Z"
  advanced_filtering_on_arrays_enabled = true
  
  subject_filter {
    case_sensitive = false
  }

  retry_policy {
    event_time_to_live    = 120
    max_delivery_attempts = 10
  }
}
