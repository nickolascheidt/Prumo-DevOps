terraform {
  backend "azurerm" {
    resource_group_name  = "rg-saasbase-tfstate"
    storage_account_name = "stsaasbasetfstate"
    container_name       = "tfstate"
    key                  = "core.tfstate"
    use_oidc             = true
  }
}
