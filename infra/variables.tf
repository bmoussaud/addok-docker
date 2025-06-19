# variables.tf
# Variable definitions for Addok on Azure Container Apps Terraform configuration

variable "environment_name" {
  description = "Name of the environment which is used to generate a short unique hash used in all resources."
  type        = string
  validation {
    condition     = length(var.environment_name) >= 1 && length(var.environment_name) <= 64
    error_message = "Environment name must be between 1 and 64 characters."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "The name of the resource group where resources will be deployed"
  type        = string
}

variable "resource_group_id" {
  description = "The ID of the resource group where resources will be deployed"
  type        = string
}

variable "acr_name" {
  description = "Name of the existing Azure Container Registry"
  type        = string
}

variable "acr_addok_importer_image_tag" {
  description = "Tag for the Addok importer image in ACR"
  type        = string
  default     = "latest"
}

variable "workers" {
  description = "Number of worker processes"
  type        = number
  default     = 1
}

variable "worker_timeout" {
  description = "Worker timeout in seconds"
  type        = number
  default     = 30
}

variable "log_queries" {
  description = "Enable query logging (1 for enabled, 0 for disabled)"
  type        = number
  default     = 1
}

variable "log_not_found" {
  description = "Enable not found logging (1 for enabled, 0 for disabled)"
  type        = number
  default     = 1
}

variable "slow_queries" {
  description = "Slow query threshold in milliseconds"
  type        = number
  default     = 200
}
