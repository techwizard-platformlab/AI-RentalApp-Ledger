terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  # Auth via ARM_* env vars (ARM_SUBSCRIPTION_ID, ARM_CLIENT_ID, ARM_TENANT_ID, ARM_USE_OIDC)
  # SP may lack provider registration rights — only pre-registered providers work.
  # Required providers for this stack:
  #   Microsoft.DBforPostgreSQL  — PostgreSQL Flexible Server
  #   Microsoft.KeyVault         — Key Vault
  #   Microsoft.ContainerService — AKS
  #   Microsoft.ContainerRegistry — ACR
  # Register manually once if needed: az provider register --namespace Microsoft.DBforPostgreSQL
  resource_provider_registrations = "none"
}

provider "azuread" {}
