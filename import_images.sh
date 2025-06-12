#!/bin/bash
set -ex

ACR_NAME="$1"

if [ -z "$ACR_NAME" ]; then
    ACR_NAME=$(azd config get-value ACR_NAME)
fi
# Log in to ACR
echo "Logging in to Azure Container Registry: $ACR_NAME"
az acr login --name "$ACR_NAME"

# Pull the image from Docker Hub
docker pull etalab/addok:latest
docker pull etalab/addok-redis:latest
docker pull nginx:latest

# Tag the image for your ACR
docker tag etalab/addok:latest "$ACR_NAME.azurecr.io/etalab/addok:latest"
docker tag etalab/addok-redis:latest "$ACR_NAME.azurecr.io/etalab/addok-redis:latest"
docker tag nginx:latest "$ACR_NAME.azurecr.io/etalab/nginx:latest"

# Push the image to your ACR
docker push "$ACR_NAME.azurecr.io/etalab/addok:latest"
docker push "$ACR_NAME.azurecr.io/etalab/addok-redis:latest"
docker push "$ACR_NAME.azurecr.io/etalab/nginx:latest"

echo "Images imported to $ACR_NAME.azurecr.io successfully."