resource "azurerm_resource_group" "core" {
  name     = "rg-saasbase-core"
  location = var.location
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.core.name
  location            = azurerm_resource_group.core.location
  sku                 = "Standard"
  admin_enabled       = false
}

resource "azurerm_role_assignment" "acr_push" {
  for_each             = toset(var.acr_pusher_object_ids)
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
}
