#!/bin/bash
set -e

TFSTATE_RESOURCE_GROUP="rg-terraform-state-fatemeh"
TFSTATE_LOCATION="westeurope"
TFSTATE_STORAGE_ACCOUNT="tfstaterestyfatemeh"
TFSTATE_CONTAINER="tfstate"
TFSTATE_KEY="restauranty.terraform.tfstate"

echo "Bootstrapping Terraform backend..."

terraform -chdir=infra/bootstrap init -input=false

terraform -chdir=infra/bootstrap apply \
  -auto-approve \
  -input=false \
  -var="resource_group_name=$TFSTATE_RESOURCE_GROUP" \
  -var="location=$TFSTATE_LOCATION" \
  -var="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
  -var="container_name=$TFSTATE_CONTAINER"

echo "Assigning Storage Blob Data Contributor role..."

STORAGE_SCOPE=$(az storage account show \
  --name "$TFSTATE_STORAGE_ACCOUNT" \
  --resource-group "$TFSTATE_RESOURCE_GROUP" \
  --query id \
  -o tsv)

USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --assignee "$USER_OBJECT_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_SCOPE" || true

echo "Waiting for Azure role assignment propagation..."
sleep 60

echo "Updating infra/versions.tf backend config..."

cat > infra/versions.tf <<EOF
terraform {
  required_version = ">= 1.8.0"

  backend "azurerm" {
    resource_group_name  = "$TFSTATE_RESOURCE_GROUP"
    storage_account_name = "$TFSTATE_STORAGE_ACCOUNT"
    container_name       = "$TFSTATE_CONTAINER"
    key                  = "$TFSTATE_KEY"

    use_azuread_auth = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
  }
}
EOF

echo "Migrating local Terraform state to Azure backend..."

terraform -chdir=infra init \
  -input=false \
  -migrate-state \
  -force-copy

echo "Done. Terraform remote state and state locking are ready."