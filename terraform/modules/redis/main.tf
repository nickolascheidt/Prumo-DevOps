# Azure retired new "Azure Cache for Redis" (classic) creation, and Azure Managed
# Redis has no free tier. For the dev environment we run Redis as a small,
# always-on Container App with INTERNAL TCP ingress, reachable by the API at
# "<name>:6379" within the same Container Apps environment.
#
# Trade-off: this cache is EPHEMERAL — its data is lost if the container restarts.
# That is acceptable for a cache in dev. Use Azure Managed Redis for prod.
resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"

  ingress {
    external_enabled = false
    transport        = "tcp"
    target_port      = 6379
    exposed_port     = 6379
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "redis"
      image  = var.image
      cpu    = var.cpu
      memory = var.memory
    }
  }
}
