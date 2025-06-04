#!/bin/bash

# Usage: ./upload.sh <resource-group> <account-name>
#set -x
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <resource-group> <account-name>"
  exit 1
fi
RESOURCE_GROUP="$1"
ACCOUNT_NAME="$2"

# Get the storage account key
accountKey=$(az storage account keys list --account-name "$ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query [0].value -o tsv)

# Create the file share if it doesn't exist
#az storage share create --name addokfileshare --account-name "$ACCOUNT_NAME" --account-key "$accountKey"


# Upload the zip file to the addok-data directory in the file share
if [ ! -f addok-france-bundle.zip ]; then
  echo "File addok-france-bundle.zip not found!"
  echo "Downloading addok-france-bundle.zip from https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip"
  wget https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip
fi

if [ ! -f addok-france-bundle.zip ]; then
  echo "Failed to download addok-france-bundle.zip. Please check the URL or your internet connection."
  exit 1
fi

if [ ! -d addok-data ]; then
    echo "Creating directory addok-data..."
    mkdir addok-data
    echo "Unzipping addok-france-bundle.zip into addok-data directory..."
    unzip -d addok-data addok-france-bundle.zip
    if [ $? -ne 0 ]; then
        echo "Failed to unzip addok-france-bundle.zip. Please check the file."
        exit 1
    fi
fi

set -x
az storage directory create --share-name addokfileshare --name addok --account-name "$ACCOUNT_NAME" --account-key "$accountKey"
az storage directory create --share-name addokfileshare --name redis --account-name "$ACCOUNT_NAME" --account-key "$accountKey"
az storage directory create --share-name addokfileshare --name data --account-name "$ACCOUNT_NAME" --account-key "$accountKey"
set +x
echo "Uploading all files from addok-data directory to Azure File Share..."

set -x
az storage file upload --source "addok-data/addok.conf" --share-name addokfileshare --account-name $ACCOUNT_NAME --account-key "$accountKey" --path "addok/addok.conf"
az storage file upload --source "addok-data/dump.rdb" --share-name addokfileshare --account-name $ACCOUNT_NAME --account-key "$accountKey" --path "redis/dump.rdb"
az storage file upload --source "addok-data/addok.db" --share-name addokfileshare --account-name $ACCOUNT_NAME --account-key "$accountKey" --path "data/addok.db"
set +x
echo "All files uploaded successfully to Azure File Share."