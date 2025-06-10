output "addok_fqdn" {
  description = "The FQDN of the Addok Container App"
  value       = azurerm_container_app.addok_app.latest_revision_fqdn
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.addok_data.name
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_instrumentation_key" {
  description = "The instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "container_app_environment_id" {
  description = "The ID of the Container App Environment"
  value       = azurerm_container_app_environment.main.id
}
