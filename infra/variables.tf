variable "environment_name" {
  description = "Name of the environment which is used to generate a short unique hash used in all resources."
  type        = string
  validation {
    condition     = length(var.environment_name) >= 1 && length(var.environment_name) <= 64
    error_message = "Environment name must be between 1 and 64 characters."
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "East US"
}

variable "workers" {
  description = "Number of workers for Addok"
  type        = number
  default     = 1
}

variable "worker_timeout" {
  description = "Worker timeout for Addok"
  type        = number
  default     = 30
}

variable "log_queries" {
  description = "Enable query logging (1 = enabled, 0 = disabled)"
  type        = number
  default     = 1
}

variable "log_not_found" {
  description = "Enable not found logging (1 = enabled, 0 = disabled)"
  type        = number
  default     = 1
}

variable "slow_queries" {
  description = "Slow query threshold in milliseconds"
  type        = number
  default     = 200
}
