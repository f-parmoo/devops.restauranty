terraform {
  required_version = ">= 1.8.0"

  backend "azurerm" {
    resource_group_name  = "rg-terraform-state-fatemeh"
    storage_account_name = "tfstaterestyfatemeh"
    container_name       = "tfstate"
    key                  = "restauranty.terraform.tfstate"

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
