#!/bin/bash

# Variables
DEPLOYMENT_NAME="test-ca-deployment"
TEMPLATE_FILE="main.bicep"

# Deploy the Bicep template and show progress
az stack sub create \
    --name $DEPLOYMENT_NAME \
    --location 'UK South' \
    --template-file $TEMPLATE_FILE \
    --action-on-unmanage 'deleteAll' \
    --deny-settings-mode 'None' \
    --tags env='test' \