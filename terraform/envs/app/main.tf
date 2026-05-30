locals {
  suffix       = var.env
  api_image    = "${data.azurerm_container_registry.acr.login_server}/saasbase-api:${var.api_image_tag}"
  web_image    = "${data.azurerm_container_registry.acr.login_server}/saasbase-web:${var.web_image_tag}"
  api_app_name = "ca-api-${local.suffix}"
  web_app_name = "ca-web-${local.suffix}"
  api_fqdn     = "${local.api_app_name}.${module.app_env.default_domain}"
  web_fqdn     = "${local.web_app_name}.${module.app_env.default_domain}"
}

data "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group
}

resource "azurerm_resource_group" "env" {
  name     = "rg-saasbase-${local.suffix}"
  location = var.location
}

module "app_env" {
  source              = "../../modules/app-environment"
  name                = "cae-saasbase-${local.suffix}"
  resource_group_name = azurerm_resource_group.env.name
  location            = azurerm_resource_group.env.location
}

module "postgres" {
  source                 = "../../modules/postgres"
  name                   = "psql-saasbase-${local.suffix}"
  resource_group_name    = azurerm_resource_group.env.name
  location               = azurerm_resource_group.env.location
  administrator_password = var.postgres_admin_password
}

module "redis" {
  source              = "../../modules/redis"
  name                = "redis-saasbase-${local.suffix}"
  resource_group_name = azurerm_resource_group.env.name
  location            = azurerm_resource_group.env.location
}

module "web" {
  source                       = "../../modules/container-app"
  name                         = local.web_app_name
  resource_group_name          = azurerm_resource_group.env.name
  container_app_environment_id = module.app_env.id
  acr_id                       = data.azurerm_container_registry.acr.id
  acr_login_server             = data.azurerm_container_registry.acr.login_server
  image                        = local.web_image
  target_port                  = 8080
  env = {
    API_URL  = "https://${local.api_fqdn}"
    API_HOST = local.api_fqdn
  }
}

module "key_vault" {
  source              = "../../modules/keyvault"
  name                = "kv-saasbase-${local.suffix}"
  resource_group_name = azurerm_resource_group.env.name
  location            = azurerm_resource_group.env.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  admin_principal_id  = data.azurerm_client_config.current.object_id
  reader_principal_ids = [
    module.api.principal_id
  ]
  secrets = {
    "ConnectionStrings--DefaultConnection" = module.postgres.connection_string
    "ConnectionStrings--Redis"             = module.redis.connection_string
    "Jwt--Key"                             = var.jwt_key
  }
}

module "api" {
  source                       = "../../modules/container-app"
  name                         = local.api_app_name
  resource_group_name          = azurerm_resource_group.env.name
  container_app_environment_id = module.app_env.id
  acr_id                       = data.azurerm_container_registry.acr.id
  acr_login_server             = data.azurerm_container_registry.acr.login_server
  image                        = local.api_image
  target_port                  = 8080
  liveness_path                = "/health/live"
  readiness_path               = "/health/ready"
  env = {
    ASPNETCORE_ENVIRONMENT    = "Production"
    ASPNETCORE_HTTP_PORTS     = "8080"
    "Jwt__Issuer"             = var.jwt_issuer
    "Jwt__Audience"           = var.jwt_audience
    "Cors__AllowedOrigins__0" = "https://${local.web_fqdn}"
  }
  secret_env = {
    "ConnectionStrings__DefaultConnection" = module.key_vault.secret_ids["ConnectionStrings--DefaultConnection"]
    "ConnectionStrings__Redis"             = module.key_vault.secret_ids["ConnectionStrings--Redis"]
    "Jwt__Key"                             = module.key_vault.secret_ids["Jwt--Key"]
  }
}
