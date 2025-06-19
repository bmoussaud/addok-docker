# outputs.tf
# Output values for Addok on Azure Container Apps Terraform configuration

output "addok_fqdn" {
  description = "The FQDN of the Addok application"
  value       = azurerm_container_app.addok_app.latest_revision_fqdn
}

output "storage_account_name" {
  description = "The name of the storage account"
  value       = azurerm_storage_account.addok_data.name
}

output "acr_name" {
  description = "The name of the Azure Container Registry"
  value       = data.azurerm_container_registry.addok_registry.name
}

output "azure_container_registry_endpoint" {
  description = "The login server endpoint of the Azure Container Registry"
  value       = data.azurerm_container_registry.addok_registry.login_server
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.log_analytics.id
}

output "application_insights_id" {
  description = "The ID of the Application Insights component"
  value       = azurerm_application_insights.app_insights.id
}

output "container_app_environment_id" {
  description = "The ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.container_env.id
}

output "resource_token" {
  description = "The unique resource token used for naming"
  value       = local.resource_token
}
