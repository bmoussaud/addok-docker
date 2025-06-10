# Addok Infrastructure with Terraform

This directory contains Terraform configuration files to deploy the Addok application stack on Azure Container Apps.

## Prerequisites

1. Install Terraform (if not already installed):
   ```bash
   # On Windows using winget
   winget install HashiCorp.Terraform
   
   # On Linux/macOS using package manager or download from https://terraform.io
   ```

2. Install Azure CLI and login:
   ```bash
   az login
   ```

3. Set your Azure subscription:
   ```bash
   az account set --subscription "your-subscription-id"
   ```

## Infrastructure Components

The Terraform configuration provisions the following Azure resources:

- **Resource Group**: Container for all resources
- **Log Analytics Workspace**: For logging and monitoring
- **Application Insights**: For application performance monitoring
- **Storage Account**: For persistent data storage
- **Azure File Shares**: For shared storage between containers
- **Container Apps Environment**: Hosting environment for containers
- **Container App**: Multi-container app with Addok and Redis

## Deployment Steps

1. **Initialize Terraform**:
   ```bash
   cd infra
   terraform init
   ```

2. **Create terraform.tfvars file**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
   
   Edit `terraform.tfvars` and customize the values:
   ```hcl
   environment_name = "your-addok-env"
   location         = "East US"
   workers          = 1
   worker_timeout   = 30
   log_queries      = 1
   log_not_found    = 1
   slow_queries     = 200
   ```

3. **Validate the configuration**:
   ```bash
   terraform validate
   ```

4. **Plan the deployment**:
   ```bash
   terraform plan
   ```

5. **Apply the configuration**:
   ```bash
   terraform apply -auto-approve
   ```

## Environment Variables

You can also set variables using environment variables with the `TF_VAR_` prefix:

```bash
export TF_VAR_environment_name="addok-prod"
export TF_VAR_location="West Europe"
export TF_VAR_workers=2
```

## Outputs

After successful deployment, Terraform will output:

- `addok_fqdn`: The public URL of your Addok application
- `storage_account_name`: Name of the storage account
- `resource_group_name`: Name of the resource group
- `log_analytics_workspace_id`: ID of the Log Analytics workspace

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Using with Azure Developer CLI (azd)

This configuration is compatible with Azure Developer CLI. You can use:

```bash
azd up
```

The `azure.yaml` file is configured to use Terraform as the infrastructure provider.

## Monitoring

After deployment, you can monitor your application using:

- **Azure Portal**: Navigate to your Container App
- **Application Insights**: View performance metrics and logs
- **Log Analytics**: Query detailed logs

Access the Azure portal at: https://portal.azure.com
