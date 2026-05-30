locals {
  # Container App secret names must be lowercase alphanumeric/'-'. Derive from env var name.
  secret_names = { for k, v in var.secret_env : k => lower(replace(k, "_", "-")) }
}

resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  registry {
    server   = var.acr_login_server
    identity = "System"
  }

  dynamic "secret" {
    for_each = var.secret_env
    content {
      name                = local.secret_names[secret.key]
      key_vault_secret_id = secret.value
      identity            = "System"
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.name
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env
        content {
          name        = env.key
          secret_name = local.secret_names[env.key]
        }
      }

      dynamic "liveness_probe" {
        for_each = var.liveness_path == "" ? [] : [1]
        content {
          transport = "HTTP"
          port      = var.target_port
          path      = var.liveness_path
        }
      }

      dynamic "readiness_probe" {
        for_each = var.readiness_path == "" ? [] : [1]
        content {
          transport = "HTTP"
          port      = var.target_port
          path      = var.readiness_path
        }
      }
    }
  }
}

# Grant this app's managed identity pull rights on the ACR.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.this.identity[0].principal_id
}
