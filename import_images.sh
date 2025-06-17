#!/bin/bash
set -ex

ACR_NAME="$1"

if [ -z "$ACR_NAME" ]; then
    ACR_NAME=$(azd env get-value ACR_NAME)
fi



# Log in to ACR
echo "Logging in to Azure Container Registry: $ACR_NAME"
az acr login --name "$ACR_NAME"

# Build the image in adocker import using acr
#az acr build --registry "$ACR_NAME" --image "etalab/addok:latest" addok-importer 
docker build -t "$ACR_NAME.azurecr.io/etalab/addok-importer-aca:latest" -f addok-importer/Dockerfile addok-importer
docker push "$ACR_NAME.azurecr.io/etalab/addok-importer-aca:latest"
# Generate a random number for the image tag
RAND_TAG=$RANDOM
docker tag "$ACR_NAME.azurecr.io/etalab/addok-importer-aca:latest" "$ACR_NAME.azurecr.io/etalab/addok-importer-aca:$RAND_TAG"
docker push "$ACR_NAME.azurecr.io/etalab/addok-importer-aca:$RAND_TAG"
echo "Image $ACR_NAME.azurecr.io/etalab/addok-importer-aca:$RAND_TAG pushed successfully."
azd env set ACR_ADDOK_IMPORTER_IMAGE "$ACR_NAME.azurecr.io/etalab/addok-importer-aca:$RAND_TAG"

# Check if the image already exists in ACR
if az acr repository show-tags --name "$ACR_NAME" --repository etalab/addok --query "contains(@, 'latest')" -o tsv | grep -q true; then
    echo "Image $ACR_NAME.azurecr.io/etalab/addok:latest already exists. Exiting."
    exit 0
fi
# Pull the image from Docker Hub
docker pull etalab/addok:latest
docker pull etalab/addok-redis:latest
docker pull etalab/addok-importer:latest
docker pull nginx:latest

# Tag the image for your ACR
docker tag etalab/addok:latest "$ACR_NAME.azurecr.io/etalab/addok:latest"
docker tag etalab/addok-redis:latest "$ACR_NAME.azurecr.io/etalab/addok-redis:latest"
docker tag etalab/addok-importer:latest "$ACR_NAME.azurecr.io/etalab/addok-importer:latest"
docker tag nginx:latest "$ACR_NAME.azurecr.io/etalab/nginx:latest"

# Push the image to your ACR
docker push "$ACR_NAME.azurecr.io/etalab/addok:latest"
docker push "$ACR_NAME.azurecr.io/etalab/addok-redis:latest"
docker push "$ACR_NAME.azurecr.io/etalab/addok-importer:latest"
docker push "$ACR_NAME.azurecr.io/etalab/nginx:latest"

echo "Images imported to $ACR_NAME.azurecr.io successfully."