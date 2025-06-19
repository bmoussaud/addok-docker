# Event-Driven File Upload Architecture

## Overview

The infrastructure has been updated to include an event-driven architecture that captures events whenever files are uploaded to the Azure Storage account. This enables automatic processing and notification when new files are added.

## Architecture Components

### 1. Storage Account with Event Monitoring
- **Blob Container**: `uploads` container in the storage account
- **Event Grid System Topic**: Monitors storage account events
- **File Share**: Original `addokfileshare` for container mount points

### 2. Message Queue
- **Service Bus Namespace**: `{resourceToken}-sb`
- **Queue**: `file-upload-events` - receives file upload notifications

### 3. Event Processing
- **Event Grid Subscription**: Routes `Microsoft.Storage.BlobCreated` events to Service Bus queue
- **Managed Identity**: Secure authentication between services

## How It Works

1. **File Upload**: When a file is uploaded to the `uploads` blob container
2. **Event Generation**: Azure Storage automatically generates a `BlobCreated` event
3. **Event Routing**: Event Grid captures the event and routes it to the Service Bus queue
4. **Message Processing**: Container apps can listen to the Service Bus queue for new file notifications

## Environment Variables

The following environment variables are available in your container apps:

```bash
SERVICE_BUS_NAMESPACE=https://{resourceToken}-sb.servicebus.windows.net/
SERVICE_BUS_QUEUE_NAME=file-upload-events
STORAGE_ACCOUNT_NAME={resourceToken}data
UPLOAD_CONTAINER_NAME=uploads
```

## Security

- **Managed Identity**: All services use user-assigned managed identity for authentication
- **RBAC**: Proper role assignments ensure minimal required permissions:
  - Service Bus Data Sender (Event Grid → Service Bus)
  - Service Bus Data Receiver (Container Apps → Service Bus)
  - Storage Blob Data Contributor (Container Apps → Storage)

## Usage Examples

### Uploading Files
You can upload files to the `uploads` container using:
- Azure Storage Explorer
- Azure CLI: `az storage blob upload`
- REST API calls
- SDK libraries

### Processing Events
Your application code can:
1. Listen to the Service Bus queue for new messages
2. Parse the Event Grid event payload to get file details
3. Download and process the uploaded file
4. Move files from `uploads` to the `addokfileshare` if needed

### Event Payload Example
```json
{
  "eventType": "Microsoft.Storage.BlobCreated",
  "subject": "/blobServices/default/containers/uploads/blobs/filename.txt",
  "data": {
    "api": "PutBlob",
    "url": "https://{storageaccount}.blob.core.windows.net/uploads/filename.txt",
    "contentType": "text/plain",
    "blobType": "BlockBlob"
  }
}
```

## Monitoring

- Check Service Bus queue metrics in Azure Portal
- Monitor Event Grid delivery success rates
- View application logs through Container Apps log analytics

## Alternative: Direct File Share Monitoring

If you prefer to monitor the original file share directly, you would need to implement:
- Custom file watcher in your application
- Polling mechanism to check for new files
- Or use Azure Functions with timer triggers

The current blob-based approach provides better event reliability and Azure integration.
