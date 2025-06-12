# Terraform configuration for Addok on Azure Container Apps
# This file provisions all required Azure resources for the Addok stack
# - Container Apps Environment
# - Container Apps (addok, addok-redis)
# - Storage Accounts (addok-data, logs)
# - Log Analytics Workspace
# - Application Insights

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.32.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.1"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Generate a unique resource token
resource "random_string" "resource_token" {
  length  = 13
  upper   = false
  special = false
  numeric = true
}

# Data source for current subscription
data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.environment_name}"
  location = var.location

  tags = {
    "azd-env-name" = var.environment_name
  }
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${random_string.resource_token.result}-log"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    "azd-env-name" = var.environment_name
  }
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${random_string.resource_token.result}-appi"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = {
    "azd-env-name" = var.environment_name
  }
}

# Storage Account for addok-data
resource "azurerm_storage_account" "addok_data" {
  name                     = lower("${random_string.resource_token.result}data")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  
  blob_properties {
    versioning_enabled       = false
    change_feed_enabled      = false
    default_service_version  = "2020-06-12"
    delete_retention_policy {
      days = 7
    }
  }

  share_properties {
    retention_policy {
      days = 7
    }
  }

  tags = {
    "azd-env-name" = var.environment_name
  }
}

# Azure File Share for Addok data
resource "azurerm_storage_share" "addok_file_share" {
  name                 = "addokfileshare"
  storage_account_name = azurerm_storage_account.addok_data.name
  quota                = 10
  access_tier          = "Hot"
}

# Azure File Share for Addok logs
resource "azurerm_storage_share" "addok_log_file_share" {
  name                 = "addoklogfileshare"
  storage_account_name = azurerm_storage_account.addok_data.name
  quota                = 10
  access_tier          = "Hot"
}

# Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = var.environment_name
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  workload_profile {
    name                  = "appProfile"
    workload_profile_type = "D4"
    minimum_count         = 1
    maximum_count         = 2
  }

  tags = {
    "azd-env-name" = var.environment_name
  }
}

# Container App Environment Storage for addok file share
resource "azurerm_container_app_environment_storage" "addok_file_share" {
  name                         = "addokfileshare"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.addok_data.name
  share_name                   = azurerm_storage_share.addok_file_share.name
  access_key                   = azurerm_storage_account.addok_data.primary_access_key
  access_mode                  = "ReadWrite"
}

# Container App Environment Storage for addok log file share
resource "azurerm_container_app_environment_storage" "addok_log_file_share" {
  name                         = "addoklogfileshare"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.addok_data.name
  share_name                   = azurerm_storage_share.addok_log_file_share.name
  access_key                   = azurerm_storage_account.addok_data.primary_access_key
  access_mode                  = "ReadWrite"
}

# Container App: addok
resource "azurerm_container_app" "addok_app" {
  name                         = "addokapp"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
  workload_profile_name        = "appProfile"

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "addok"
      image  = "etalab/addok"
      cpu    = 1
      memory = "2.0Gi"

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
        value = "localhost"
      }

      env {
        name  = "REDIS_PORT"
        value = "6379"
      }

      liveness_probe {
        transport      = "TCP"
        port           = 7878
        interval_seconds = 5
        timeout         = 5
        failure_count_threshold = 10
      }

      readiness_probe {
        transport      = "TCP"
        port           = 7878
        interval_seconds = 5
        timeout         = 5
        failure_count_threshold = 10
      }

      startup_probe {
        transport      = "TCP"
        port           = 7878
        interval_seconds = 5
        timeout         = 5
        failure_count_threshold = 10
      }

      volume_mounts {
        name = "share-volume"
        path = "/data"
        sub_path = "data"
      }

      volume_mounts {
        name = "share-volume"
        path = "/etc/addok"
        sub_path = "addok"
      }

      volume_mounts {
        name = "logs-volume"
        path = "/logs"
      }
    }

    container {
      name   = "addok-redis"
      image  = "etalab/addok-redis"
      cpu    = 2
      memory = "6.0Gi"

      liveness_probe {
        transport      = "TCP"
        port           = 6379
        interval_seconds = 30
        timeout         = 240
        failure_count_threshold = 10
      }

      readiness_probe {
        transport      = "TCP"
        port           = 6379
        interval_seconds = 30
        timeout         = 240
        failure_count_threshold = 10
      }

      startup_probe {
        transport      = "TCP"
        port           = 6379
        interval_seconds = 30
        timeout         = 240
        failure_count_threshold = 10
      }

      volume_mounts {
        name = "share-volume"
        path = "/data"
        sub_path = "redis"
      }
    }

    volume {
      name         = "share-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.addok_file_share.name
    }

    volume {
      name         = "logs-volume"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.addok_log_file_share.name
    }
  }

  ingress {
    external_enabled = true
    target_port      = 7878
    traffic_weight {
      percentage = 100
      latest_revision = true
    }
  }

  tags = {
    "azd-env-name" = var.environment_name
  }

  depends_on = [
    azurerm_container_app_environment_storage.addok_file_share,
    azurerm_container_app_environment_storage.addok_log_file_share
  ]
}
