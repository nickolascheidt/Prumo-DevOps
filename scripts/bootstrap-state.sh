#!/usr/bin/env bash
# Creates the Azure resources Terraform needs for remote state.
# Run once per subscription. Requires: az login already done.
set -euo pipefail

LOCATION="${LOCATION:-brazilsouth}"
STATE_RG="rg-saasbase-tfstate"
STATE_SA="stsaasbasetfstate"          # must be globally unique; 3-24 lowercase alnum
STATE_CONTAINER="tfstate"

echo "Creating state resource group ${STATE_RG}..."
az group create --name "$STATE_RG" --location "$LOCATION" --output none

echo "Creating state storage account ${STATE_SA}..."
az storage account create \
  --name "$STATE_SA" --resource-group "$STATE_RG" \
  --sku Standard_LRS --encryption-services blob \
  --min-tls-version TLS1_2 --allow-blob-public-access false --output none

echo "Creating state container ${STATE_CONTAINER}..."
az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_SA" \
  --auth-mode login --output none

echo "Done. Backend config:"
echo "  resource_group_name  = \"$STATE_RG\""
echo "  storage_account_name = \"$STATE_SA\""
echo "  container_name       = \"$STATE_CONTAINER\""
