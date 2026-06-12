# SaaSBasePlatform-DevOps — CI/CD Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a dedicated repo that provisions Azure infrastructure with Terraform and deploys the .NET API and Angular SPA to Azure Container Apps via GitHub Actions, with the two app repos building/pushing their own images and triggering deploys.

**Architecture:** The orchestrator repo owns all Terraform (one shared ACR + per-env Container Apps, managed PostgreSQL, managed Redis, Key Vault, Log Analytics). Each app repo builds a container image, pushes it to ACR by commit SHA, and fires a `repository_dispatch` at the orchestrator, which records the new tag in a git-tracked tfvars file and runs `terraform apply`. Auth to Azure is OIDC (no stored cloud secrets). `dev` auto-deploys from `main`; `prod` deploys via gated `workflow_dispatch`.

**Tech Stack:** Terraform (`azurerm` ~> 4.x), Azure Container Apps, Azure Database for PostgreSQL Flexible Server, Azure Cache for Redis, Azure Key Vault, GitHub Actions (OIDC), Docker (multi-stage), nginx, .NET 10, Angular 18.

**Repo paths used in this plan:**
- Orchestrator: `~/source/repos/SaaSBasePlatform-DevOps` (this repo)
- Backend: `~/source/repos/SaaSBasePlatform`
- Frontend: `~/source/repos/SaaSBasePlatform-Angular`

**GitHub identifiers:** `nickolascheidt/SaaSBasePlatform-DevOps`, `nickolascheidt/SaaSBasePlatform`, `nickolascheidt/SaaSBasePlatform-Angular`.

**Naming convention:** `<kind>-saasbase-<env>` (e.g. `rg-saasbase-dev`). Core/shared resources use `<kind>saasbasecore` where names must be globally unique and alphanumeric (ACR, storage).

---

## Verification model for infra

Terraform and Docker don't have red/green unit tests, so each task's "test" step is a concrete validation command with expected output:
- Terraform: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`.
- Dockerfiles: `docker build` produces an image.
- Workflows: `actionlint` (if installed) or YAML parse; otherwise a documented dry-run via `workflow_dispatch` after merge.

Run all `terraform` commands from the directory named in each task.

---

## Phase 0 — Bootstrap (one-time, scripted + documented)

### Task 1: Bootstrap script for Terraform remote state

**Files:**
- Create: `scripts/bootstrap-state.sh`

- [ ] **Step 1: Write the bootstrap script**

```bash
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
```

- [ ] **Step 2: Verify the script is syntactically valid**

Run: `bash -n scripts/bootstrap-state.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-state.sh
git commit -m "chore: add Terraform remote-state bootstrap script"
```

### Task 2: Bootstrap script for OIDC identities and role assignments

**Files:**
- Create: `scripts/bootstrap-oidc.sh`

This creates one Entra app registration per repo and federated credentials so GitHub Actions can authenticate to Azure with no stored secrets. Backend/frontend identities get `AcrPush`; the orchestrator identity gets `Contributor` + `Role Based Access Control Administrator` (needed because Terraform creates role assignments).

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Creates Entra app registrations + GitHub OIDC federated credentials.
# Run once. Requires: az login with permission to create app registrations and assign roles.
set -euo pipefail

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
GH_OWNER="nickolascheidt"
ORCHESTRATOR_REPO="SaaSBasePlatform-DevOps"
BACKEND_REPO="SaaSBasePlatform"
FRONTEND_REPO="SaaSBasePlatform-Angular"

create_app() {
  local name="$1"
  local app_id
  app_id="$(az ad app create --display-name "$name" --query appId -o tsv)"
  az ad sp create --id "$app_id" --output none 2>/dev/null || true
  echo "$app_id"
}

add_fed_cred() {
  local app_id="$1" name="$2" subject="$3"
  az ad app federated-credential create --id "$app_id" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none
}

echo "== Orchestrator identity =="
ORCH_APP_ID="$(create_app "gh-${ORCHESTRATOR_REPO}")"
add_fed_cred "$ORCH_APP_ID" "main"        "repo:${GH_OWNER}/${ORCHESTRATOR_REPO}:ref:refs/heads/main"
add_fed_cred "$ORCH_APP_ID" "env-dev"     "repo:${GH_OWNER}/${ORCHESTRATOR_REPO}:environment:dev"
add_fed_cred "$ORCH_APP_ID" "env-prod"    "repo:${GH_OWNER}/${ORCHESTRATOR_REPO}:environment:prod"
ORCH_SP_ID="$(az ad sp show --id "$ORCH_APP_ID" --query id -o tsv)"
az role assignment create --assignee-object-id "$ORCH_SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/subscriptions/${SUBSCRIPTION_ID}" --output none
az role assignment create --assignee-object-id "$ORCH_SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope "/subscriptions/${SUBSCRIPTION_ID}" --output none

echo "== Backend identity =="
BE_APP_ID="$(create_app "gh-${BACKEND_REPO}")"
add_fed_cred "$BE_APP_ID" "main" "repo:${GH_OWNER}/${BACKEND_REPO}:ref:refs/heads/main"

echo "== Frontend identity =="
FE_APP_ID="$(create_app "gh-${FRONTEND_REPO}")"
add_fed_cred "$FE_APP_ID" "main" "repo:${GH_OWNER}/${FRONTEND_REPO}:ref:refs/heads/main"

echo ""
echo "Tenant ID:        $(az account show --query tenantId -o tsv)"
echo "Subscription ID:  $SUBSCRIPTION_ID"
echo "ORCHESTRATOR AZURE_CLIENT_ID: $ORCH_APP_ID"
echo "BACKEND      AZURE_CLIENT_ID: $BE_APP_ID"
echo "FRONTEND     AZURE_CLIENT_ID: $FE_APP_ID"
echo ""
echo "NOTE: AcrPush for backend/frontend SPs is granted by core Terraform (acr_pusher_object_ids)."
echo "Pass these object IDs to core: $(az ad sp show --id "$BE_APP_ID" --query id -o tsv), $(az ad sp show --id "$FE_APP_ID" --query id -o tsv)"
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/bootstrap-oidc.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add scripts/bootstrap-oidc.sh
git commit -m "chore: add OIDC identity bootstrap script"
```

---

## Phase 1 — Terraform core (shared ACR)

### Task 3: Core Terraform — providers, backend, variables

**Files:**
- Create: `terraform/core/versions.tf`
- Create: `terraform/core/backend.tf`
- Create: `terraform/core/variables.tf`

- [ ] **Step 1: Write `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

- [ ] **Step 2: Write `backend.tf`**

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-saasbase-tfstate"
    storage_account_name = "stsaasbasetfstate"
    container_name       = "tfstate"
    key                  = "core.tfstate"
    use_oidc             = true
  }
}
```

- [ ] **Step 3: Write `variables.tf`**

```hcl
variable "location" {
  type    = string
  default = "brazilsouth"
}

variable "acr_name" {
  type        = string
  default     = "acrsaasbasecore"
  description = "Globally-unique ACR name (alphanumeric)."
}

variable "acr_pusher_object_ids" {
  type        = list(string)
  default     = []
  description = "Service principal object IDs (backend + frontend GitHub identities) granted AcrPush."
}
```

- [ ] **Step 4: Verify formatting and validate**

Run: `cd terraform/core && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `fmt` produces no output; `validate` prints `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/core
git commit -m "feat(core): add Terraform providers, backend, variables"
```

### Task 4: Core Terraform — ACR resource and outputs

**Files:**
- Create: `terraform/core/main.tf`
- Create: `terraform/core/outputs.tf`

- [ ] **Step 1: Write `main.tf`**

```hcl
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
```

- [ ] **Step 2: Write `outputs.tf`**

```hcl
output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_id" {
  value = azurerm_container_registry.acr.id
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}
```

- [ ] **Step 3: Validate**

Run: `cd terraform/core && terraform fmt -check && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add terraform/core
git commit -m "feat(core): provision shared ACR with AcrPush role assignments"
```

---

## Phase 2 — Terraform modules

### Task 5: Module — PostgreSQL Flexible Server

**Files:**
- Create: `terraform/modules/postgres/variables.tf`
- Create: `terraform/modules/postgres/main.tf`
- Create: `terraform/modules/postgres/outputs.tf`

- [ ] **Step 1: Write `variables.tf`**

```hcl
variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "administrator_login" {
  type    = string
  default = "saasadmin"
}
variable "administrator_password" {
  type      = string
  sensitive = true
}
variable "database_name" {
  type    = string
  default = "SaaSBasePlatformDb"
}
variable "sku_name" {
  type    = string
  default = "B_Standard_B1ms"
}
variable "storage_mb" {
  type    = number
  default = 32768
}
```

- [ ] **Step 2: Write `main.tf`**

```hcl
resource "azurerm_postgresql_flexible_server" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "16"
  administrator_login           = var.administrator_login
  administrator_password        = var.administrator_password
  sku_name                      = var.sku_name
  storage_mb                    = var.storage_mb
  public_network_access_enabled = true
  zone                          = "1"
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Allow other Azure services (Container Apps egress) to reach the server.
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
```

- [ ] **Step 3: Write `outputs.tf`**

The connection string matches the API's Npgsql format (`ConnectionStrings:DefaultConnection`).

```hcl
output "connection_string" {
  value     = "Host=${azurerm_postgresql_flexible_server.this.fqdn};Port=5432;Database=${var.database_name};Username=${var.administrator_login};Password=${var.administrator_password};SslMode=Require;Trust Server Certificate=true"
  sensitive = true
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/postgres && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/postgres
git commit -m "feat(modules): add postgres flexible server module"
```

### Task 6: Module — Redis Cache

**Files:**
- Create: `terraform/modules/redis/variables.tf`
- Create: `terraform/modules/redis/main.tf`
- Create: `terraform/modules/redis/outputs.tf`

- [ ] **Step 1: Write `variables.tf`**

```hcl
variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "capacity" {
  type    = number
  default = 0
}
variable "family" {
  type    = string
  default = "C"
}
variable "sku_name" {
  type    = string
  default = "Basic"
}
```

- [ ] **Step 2: Write `main.tf`**

```hcl
resource "azurerm_redis_cache" "this" {
  name                 = var.name
  resource_group_name  = var.resource_group_name
  location             = var.location
  capacity             = var.capacity
  family               = var.family
  sku_name             = var.sku_name
  non_ssl_port_enabled = false
  minimum_tls_version  = "1.2"
}
```

- [ ] **Step 3: Write `outputs.tf`**

StackExchange.Redis format consumed by the API at `ConnectionStrings:Redis`.

```hcl
output "connection_string" {
  value     = "${azurerm_redis_cache.this.hostname}:${azurerm_redis_cache.this.ssl_port},password=${azurerm_redis_cache.this.primary_access_key},ssl=True,abortConnect=False"
  sensitive = true
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/redis && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/redis
git commit -m "feat(modules): add redis cache module"
```

### Task 7: Module — Key Vault + secrets

**Files:**
- Create: `terraform/modules/keyvault/variables.tf`
- Create: `terraform/modules/keyvault/main.tf`
- Create: `terraform/modules/keyvault/outputs.tf`

- [ ] **Step 1: Write `variables.tf`**

```hcl
variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }

variable "secrets" {
  type        = map(string)
  sensitive   = true
  description = "Secret name => value to store in the vault."
}

variable "reader_principal_ids" {
  type        = list(string)
  default     = []
  description = "Object IDs granted Key Vault Secrets User (the Container Apps' managed identities)."
}

variable "admin_principal_id" {
  type        = string
  description = "Object ID of the deploying identity (needs to write secrets)."
}
```

- [ ] **Step 2: Write `main.tf`**

Uses RBAC authorization (not access policies).

```hcl
resource "azurerm_key_vault" "this" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
}

resource "azurerm_role_assignment" "admin" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.admin_principal_id
}

resource "azurerm_role_assignment" "readers" {
  for_each             = toset(var.reader_principal_ids)
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

resource "azurerm_key_vault_secret" "this" {
  for_each     = var.secrets
  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.admin]
}
```

- [ ] **Step 3: Write `outputs.tf`**

```hcl
output "vault_id" {
  value = azurerm_key_vault.this.id
}

output "secret_ids" {
  value = { for k, s in azurerm_key_vault_secret.this : k => s.versionless_id }
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/keyvault && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/keyvault
git commit -m "feat(modules): add key vault module with RBAC secrets"
```

### Task 8: Module — Container Apps Environment + Log Analytics

**Files:**
- Create: `terraform/modules/app-environment/variables.tf`
- Create: `terraform/modules/app-environment/main.tf`
- Create: `terraform/modules/app-environment/outputs.tf`

- [ ] **Step 1: Write `variables.tf`**

```hcl
variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
```

- [ ] **Step 2: Write `main.tf`**

```hcl
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "this" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
}
```

- [ ] **Step 3: Write `outputs.tf`**

```hcl
output "id" {
  value = azurerm_container_app_environment.this.id
}

output "default_domain" {
  value = azurerm_container_app_environment.this.default_domain
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/app-environment && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/app-environment
git commit -m "feat(modules): add container apps environment + log analytics"
```

### Task 9: Module — Container App

A single reusable module for both API and web. It uses a system-assigned managed identity for ACR pull and (optionally) Key Vault secret references.

**Files:**
- Create: `terraform/modules/container-app/variables.tf`
- Create: `terraform/modules/container-app/main.tf`
- Create: `terraform/modules/container-app/outputs.tf`

- [ ] **Step 1: Write `variables.tf`**

```hcl
variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "container_app_environment_id" { type = string }
variable "acr_id" { type = string }
variable "acr_login_server" { type = string }
variable "image" {
  type        = string
  description = "Full image reference, e.g. acr.azurecr.io/saasbase-api:<sha>."
}
variable "target_port" { type = number }
variable "cpu" {
  type    = number
  default = 0.5
}
variable "memory" {
  type    = string
  default = "1Gi"
}
variable "min_replicas" {
  type    = number
  default = 1
}
variable "max_replicas" {
  type    = number
  default = 3
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Plain (non-secret) environment variables."
}

variable "secret_env" {
  type        = map(string)
  default     = {}
  description = "Env var name => Key Vault versionless secret ID. Surfaced as Container App secrets."
}

variable "liveness_path" {
  type    = string
  default = ""
}
variable "readiness_path" {
  type    = string
  default = ""
}
```

- [ ] **Step 2: Write `main.tf`**

```hcl
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
```

- [ ] **Step 3: Write `outputs.tf`**

```hcl
output "fqdn" {
  value = azurerm_container_app.this.ingress[0].fqdn
}

output "principal_id" {
  value = azurerm_container_app.this.identity[0].principal_id
}

output "url" {
  value = "https://${azurerm_container_app.this.ingress[0].fqdn}"
}
```

- [ ] **Step 4: Validate**

Run: `cd terraform/modules/container-app && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/container-app
git commit -m "feat(modules): add reusable container app module"
```

> **Note on Key Vault ↔ Container App ordering:** the container-app module's managed identity must have `Key Vault Secrets User` before the app can resolve `key_vault_secret_id`. The env composition (Task 10) handles this by creating the apps first, then granting their principal IDs as Key Vault readers, then the apps' secret references resolve on the next revision. To avoid a two-apply bootstrap, the env passes `secret_env = {}` is NOT used; instead grant happens via the keyvault module's `reader_principal_ids` referencing the app principal IDs, and `azurerm_key_vault_secret` + role assignment are created before the container app secret blocks resolve. Terraform resolves this dependency graph automatically because the app's `key_vault_secret_id` references the keyvault module output. If the very first apply reports a transient secret-resolution error, re-run `terraform apply` once.

---

## Phase 3 — Terraform environments

### Task 10: Environment composition (root module reused by dev and prod)

Both environments share one root configuration in `terraform/envs/app`, selected by `*.tfvars` + a distinct state key. This avoids duplicating HCL.

**Files:**
- Create: `terraform/envs/app/versions.tf`
- Create: `terraform/envs/app/variables.tf`
- Create: `terraform/envs/app/main.tf`
- Create: `terraform/envs/app/outputs.tf`

- [ ] **Step 1: Write `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  backend "azurerm" {
    use_oidc = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}
```

- [ ] **Step 2: Write `variables.tf`**

```hcl
variable "env" { type = string }
variable "location" {
  type    = string
  default = "brazilsouth"
}

variable "acr_resource_group" {
  type    = string
  default = "rg-saasbase-core"
}
variable "acr_name" {
  type    = string
  default = "acrsaasbasecore"
}

variable "api_image_tag" {
  type        = string
  default     = "latest"
  description = "Image tag (app repo commit SHA) for the API container."
}
variable "web_image_tag" {
  type        = string
  default     = "latest"
  description = "Image tag (app repo commit SHA) for the web container."
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}
variable "jwt_key" {
  type      = string
  sensitive = true
}
variable "jwt_issuer" {
  type    = string
  default = "SaaS_BasePlatformApi"
}
variable "jwt_audience" {
  type    = string
  default = "SaaS_BasePlatformClient"
}
```

- [ ] **Step 3: Write `main.tf`**

Both Container Apps derive their FQDNs from the environment's `default_domain` (FQDN = `<app-name>.<default_domain>`), so the API and web modules never reference each other — no dependency cycle.

```hcl
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
    API_URL = "https://${local.api_fqdn}"
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
```

- [ ] **Step 4: Write `outputs.tf`**

```hcl
output "api_url" {
  value = module.api.url
}
output "web_url" {
  value = module.web.url
}
```

- [ ] **Step 5: Validate**

Run: `cd terraform/envs/app && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add terraform/envs/app
git commit -m "feat(envs): add shared environment composition for api + web"
```

### Task 11: Per-env backend configs and tfvars

**Files:**
- Create: `terraform/envs/app/backends/dev.hcl`
- Create: `terraform/envs/app/backends/prod.hcl`
- Create: `terraform/envs/app/dev.tfvars`
- Create: `terraform/envs/app/prod.tfvars`
- Create: `terraform/envs/app/images.dev.auto.tfvars.json`
- Create: `terraform/envs/app/images.prod.auto.tfvars.json`

- [ ] **Step 1: Write `backends/dev.hcl`**

```hcl
resource_group_name  = "rg-saasbase-tfstate"
storage_account_name = "stsaasbasetfstate"
container_name       = "tfstate"
key                  = "app-dev.tfstate"
```

- [ ] **Step 2: Write `backends/prod.hcl`**

```hcl
resource_group_name  = "rg-saasbase-tfstate"
storage_account_name = "stsaasbasetfstate"
container_name       = "tfstate"
key                  = "app-prod.tfstate"
```

- [ ] **Step 3: Write `dev.tfvars`**

```hcl
env      = "dev"
location = "brazilsouth"
```

- [ ] **Step 4: Write `prod.tfvars`**

```hcl
env      = "prod"
location = "brazilsouth"
```

- [ ] **Step 5: Write `images.dev.auto.tfvars.json`**

The deploy workflow rewrites only the changed key on each deploy. Terraform auto-loads `*.auto.tfvars.json`, but since both envs share one root dir, the workflow renames the correct file to `images.auto.tfvars.json` at deploy time (Task 13). Seed both with `latest`:

```json
{
  "api_image_tag": "latest",
  "web_image_tag": "latest"
}
```

- [ ] **Step 6: Write `images.prod.auto.tfvars.json`** (identical seed)

```json
{
  "api_image_tag": "latest",
  "web_image_tag": "latest"
}
```

- [ ] **Step 7: Add `.gitignore` for the active auto-tfvars symlink/copy**

Create `terraform/envs/app/.gitignore`:

```gitignore
images.auto.tfvars.json
.terraform/
*.tfplan
```

- [ ] **Step 8: Verify JSON is valid**

Run: `cat terraform/envs/app/images.dev.auto.tfvars.json | python -c "import sys,json; json.load(sys.stdin); print('ok')"`
Expected: `ok`

- [ ] **Step 9: Commit**

```bash
git add terraform/envs/app
git commit -m "feat(envs): add per-env backend configs, tfvars, and image tag files"
```

---

## Phase 4 — Orchestrator workflows

### Task 12: PR plan workflow

**Files:**
- Create: `.github/workflows/infra-plan.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: infra-plan

on:
  pull_request:
    paths:
      - "terraform/**"
      - ".github/workflows/infra-plan.yml"

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: [dev, prod]
    environment: ${{ matrix.env }}
    defaults:
      run:
        working-directory: terraform/envs/app
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.9.8"

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Select image tag file
        run: cp images.${{ matrix.env }}.auto.tfvars.json images.auto.tfvars.json

      - name: Terraform init
        env:
          ARM_USE_OIDC: "true"
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        run: terraform init -backend-config=backends/${{ matrix.env }}.hcl

      - name: Terraform fmt check
        run: terraform fmt -check -recursive ..

      - name: Terraform plan
        env:
          ARM_USE_OIDC: "true"
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_postgres_admin_password: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
          TF_VAR_jwt_key: ${{ secrets.JWT_KEY }}
        run: terraform plan -var-file=${{ matrix.env }}.tfvars -input=false
```

- [ ] **Step 2: Validate YAML**

Run: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/infra-plan.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/infra-plan.yml
git commit -m "ci: add terraform PR plan workflow"
```

### Task 13: Deploy workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

Handles two entry points: `repository_dispatch` (type `deploy`, always targets `dev`) and `workflow_dispatch` (manual, choose env/app/tag — used for `prod`). It rewrites the per-env image tag file, commits it, then applies.

- [ ] **Step 1: Write the workflow**

```yaml
name: deploy

on:
  repository_dispatch:
    types: [deploy]
  workflow_dispatch:
    inputs:
      env:
        description: "Target environment"
        type: choice
        options: [dev, prod]
        required: true
      app:
        description: "Which app image to update"
        type: choice
        options: [api, web]
        required: true
      image_tag:
        description: "Image tag (app repo commit SHA)"
        type: string
        required: true

permissions:
  id-token: write
  contents: write

jobs:
  resolve:
    runs-on: ubuntu-latest
    outputs:
      env: ${{ steps.r.outputs.env }}
      app: ${{ steps.r.outputs.app }}
      tag: ${{ steps.r.outputs.tag }}
    steps:
      - id: r
        run: |
          if [ "${{ github.event_name }}" = "repository_dispatch" ]; then
            echo "env=dev" >> "$GITHUB_OUTPUT"
            echo "app=${{ github.event.client_payload.app }}" >> "$GITHUB_OUTPUT"
            echo "tag=${{ github.event.client_payload.image_tag }}" >> "$GITHUB_OUTPUT"
          else
            echo "env=${{ inputs.env }}" >> "$GITHUB_OUTPUT"
            echo "app=${{ inputs.app }}" >> "$GITHUB_OUTPUT"
            echo "tag=${{ inputs.image_tag }}" >> "$GITHUB_OUTPUT"
          fi

  deploy:
    needs: resolve
    runs-on: ubuntu-latest
    environment: ${{ needs.resolve.outputs.env }}
    defaults:
      run:
        working-directory: terraform/envs/app
    steps:
      - uses: actions/checkout@v4

      - name: Update image tag file
        run: |
          set -euo pipefail
          FILE="images.${{ needs.resolve.outputs.env }}.auto.tfvars.json"
          KEY="${{ needs.resolve.outputs.app }}_image_tag"
          TAG="${{ needs.resolve.outputs.tag }}"
          tmp="$(mktemp)"
          jq --arg k "$KEY" --arg v "$TAG" '.[$k] = $v' "$FILE" > "$tmp"
          mv "$tmp" "$FILE"
          cat "$FILE"

      - name: Commit updated tag
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add "images.${{ needs.resolve.outputs.env }}.auto.tfvars.json"
          git commit -m "deploy(${{ needs.resolve.outputs.env }}): ${{ needs.resolve.outputs.app }}=${{ needs.resolve.outputs.tag }}" || echo "no changes"
          git push

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.9.8"

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Select image tag file
        run: cp images.${{ needs.resolve.outputs.env }}.auto.tfvars.json images.auto.tfvars.json

      - name: Terraform init
        env:
          ARM_USE_OIDC: "true"
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        run: terraform init -backend-config=backends/${{ needs.resolve.outputs.env }}.hcl

      - name: Terraform apply
        env:
          ARM_USE_OIDC: "true"
          ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          TF_VAR_postgres_admin_password: ${{ secrets.POSTGRES_ADMIN_PASSWORD }}
          TF_VAR_jwt_key: ${{ secrets.JWT_KEY }}
        run: terraform apply -auto-approve -var-file=${{ needs.resolve.outputs.env }}.tfvars -input=false
```

- [ ] **Step 2: Validate YAML**

Run: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/deploy.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add deploy workflow (dispatch + manual prod)"
```

---

## Phase 5 — Documentation

### Task 14: CONTRACT, ARCHITECTURE, RUNBOOK, README

**Files:**
- Create: `docs/CONTRACT.md`
- Create: `docs/ARCHITECTURE.md`
- Create: `docs/RUNBOOK.md`
- Modify: `README.md`

- [ ] **Step 1: Write `docs/CONTRACT.md`**

````markdown
# App-repo → Orchestrator contract

Each app repo builds one image, pushes it to the shared ACR by commit SHA, then
dispatches a deploy event.

## Image names
- Backend: `<acr>.azurecr.io/saasbase-api:<git-sha>` (also `:latest`)
- Frontend: `<acr>.azurecr.io/saasbase-web:<git-sha>` (also `:latest`)

## repository_dispatch payload
Sent to `nickolascheidt/SaaSBasePlatform-DevOps`:

```json
{
  "event_type": "deploy",
  "client_payload": { "app": "api", "image_tag": "<git-sha>", "sha": "<git-sha>" }
}
```
`app` is `api` (backend) or `web` (frontend). Dispatches always deploy to **dev**.
Production is deployed manually via the orchestrator's `deploy` workflow (`workflow_dispatch`).

## Secrets the app repos need
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — OIDC login for ACR push.
- `ACR_LOGIN_SERVER` — e.g. `acrsaasbasecore.azurecr.io`.
- `DISPATCH_TOKEN` — fine-grained PAT with `contents:write` (or repo) on the orchestrator repo,
  used to send the repository_dispatch.
````

- [ ] **Step 2: Write `docs/ARCHITECTURE.md`** (copy the design's architecture + topology sections)

```markdown
# Architecture

See `docs/superpowers/specs/2026-05-30-saasbase-devops-cicd-design.md` for the full design.

- One shared ACR (`rg-saasbase-core`).
- Per env (`dev`, `prod`): resource group `rg-saasbase-<env>` containing a Container Apps
  environment (`ca-api-<env>`, `ca-web-<env>`), PostgreSQL Flexible Server, Redis Cache,
  Key Vault, and Log Analytics.
- API reads secrets (`ConnectionStrings__DefaultConnection`, `ConnectionStrings__Redis`,
  `Jwt__Key`) from Key Vault via its managed identity.
- Web (nginx) serves the SPA and proxies `/api` to the API container.
- Terraform state in `stsaasbasetfstate` (`rg-saasbase-tfstate`), keys `core`, `app-dev`, `app-prod`.
```

- [ ] **Step 3: Write `docs/RUNBOOK.md`**

````markdown
# Runbook

## One-time bootstrap
1. `az login`
2. `LOCATION=brazilsouth bash scripts/bootstrap-state.sh`
3. `bash scripts/bootstrap-oidc.sh` — note the printed client IDs and SP object IDs.
4. In each GitHub repo, add secrets:
   - Orchestrator: `AZURE_CLIENT_ID` (orchestrator), `AZURE_TENANT_ID`,
     `AZURE_SUBSCRIPTION_ID`, `POSTGRES_ADMIN_PASSWORD`, `JWT_KEY`.
   - Backend & Frontend: `AZURE_CLIENT_ID` (their own), `AZURE_TENANT_ID`,
     `AZURE_SUBSCRIPTION_ID`, `ACR_LOGIN_SERVER`, `DISPATCH_TOKEN`.
5. Create GitHub Environments `dev` and `prod` in the orchestrator repo; add required
   reviewers to `prod`.
6. Apply core once to create the ACR and grant AcrPush:
   ```bash
   cd terraform/core
   terraform init
   terraform apply -var 'acr_pusher_object_ids=["<backend-sp-oid>","<frontend-sp-oid>"]'
   ```

## First app deploy
Push to `main` in an app repo → image builds + pushes → dispatch → dev deploys.

## Manual prod deploy
Orchestrator repo → Actions → `deploy` → Run workflow → choose `env=prod`,
`app=api|web`, `image_tag=<sha>`. Approve the `prod` environment gate.

## Rollback
Re-run `deploy` (`workflow_dispatch`) with a previous `image_tag`. Container Apps keep the
prior revision; traffic only shifts after the new revision is healthy.

## Connection-string key reference (must match the API)
- `ConnectionStrings__DefaultConnection` (Npgsql)
- `ConnectionStrings__Redis` (StackExchange.Redis)
- `Jwt__Key`, `Jwt__Issuer`, `Jwt__Audience`
````

- [ ] **Step 4: Replace `README.md`**

```markdown
# SaaSBasePlatform-DevOps

CI/CD orchestration for the SaaS Base Platform: Terraform-provisioned Azure infrastructure
and GitHub Actions deployment of the .NET API and Angular SPA to Azure Container Apps.

- Design: `docs/superpowers/specs/2026-05-30-saasbase-devops-cicd-design.md`
- Architecture: `docs/ARCHITECTURE.md`
- App-repo contract: `docs/CONTRACT.md`
- Operations: `docs/RUNBOOK.md`

## Layout
- `terraform/core` — shared ACR.
- `terraform/modules` — reusable modules (postgres, redis, keyvault, app-environment, container-app).
- `terraform/envs/app` — environment composition (dev/prod via tfvars + backend configs).
- `.github/workflows` — `infra-plan` (PR), `deploy` (dispatch + manual prod).
- `scripts` — one-time bootstrap.
```

- [ ] **Step 5: Verify docs are non-empty and commit**

Run: `wc -l docs/CONTRACT.md docs/ARCHITECTURE.md docs/RUNBOOK.md README.md`
Expected: each file > 5 lines.

```bash
git add docs/CONTRACT.md docs/ARCHITECTURE.md docs/RUNBOOK.md README.md
git commit -m "docs: add contract, architecture, runbook, README"
```

---

## Phase 6 — Backend app repo (`SaaSBasePlatform`)

> All paths in this phase are under `~/source/repos/SaaSBasePlatform`. Commit in that repo.

### Task 15: Backend Dockerfile + .dockerignore

**Files:**
- Create: `~/source/repos/SaaSBasePlatform/Dockerfile`
- Create: `~/source/repos/SaaSBasePlatform/.dockerignore`

- [ ] **Step 1: Write `Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore SaaS_BasePlatform.Api/SaaS_BasePlatform.Api.csproj
RUN dotnet publish SaaS_BasePlatform.Api/SaaS_BasePlatform.Api.csproj \
    -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "SaaS_BasePlatform.Api.dll"]
```

- [ ] **Step 2: Write `.dockerignore`**

```gitignore
**/bin/
**/obj/
**/.vs/
**/.git/
**/*.user
docs/
graphify-out/
```

- [ ] **Step 3: Build to verify**

Run: `cd ~/source/repos/SaaSBasePlatform && docker build -t saasbase-api:test .`
Expected: build completes; final line `naming to docker.io/library/saasbase-api:test` (or `Successfully tagged`).

- [ ] **Step 4: Commit**

```bash
cd ~/source/repos/SaaSBasePlatform
git checkout -b ci/containerize
git add Dockerfile .dockerignore
git commit -m "ci: add multi-stage Dockerfile for the API"
```

### Task 16: Backend build-and-deploy workflow

**Files:**
- Create: `~/source/repos/SaaSBasePlatform/.github/workflows/build-and-deploy.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: build-and-deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: ACR login
        run: az acr login --name "${{ secrets.ACR_LOGIN_SERVER }}"

      - name: Build and push
        run: |
          IMAGE="${{ secrets.ACR_LOGIN_SERVER }}/saasbase-api"
          docker build -t "$IMAGE:${{ github.sha }}" -t "$IMAGE:latest" .
          docker push "$IMAGE:${{ github.sha }}"
          docker push "$IMAGE:latest"

      - name: Dispatch deploy
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.DISPATCH_TOKEN }}
          repository: nickolascheidt/SaaSBasePlatform-DevOps
          event-type: deploy
          client-payload: '{"app":"api","image_tag":"${{ github.sha }}","sha":"${{ github.sha }}"}'
```

- [ ] **Step 2: Validate YAML**

Run: `python -c "import yaml; yaml.safe_load(open('.github/workflows/build-and-deploy.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build-and-deploy.yml
git commit -m "ci: build+push API image and dispatch deploy"
```

---

## Phase 7 — Frontend app repo (`SaaSBasePlatform-Angular`)

> All paths in this phase are under `~/source/repos/SaaSBasePlatform-Angular`. Commit in that repo.

### Task 17: Wire the SPA to a relative API URL for production

The SPA currently hardcodes `http://localhost:5201/api` in `ApiService` and the production
build does not swap environment files. Make production use a relative `/api` (served by nginx).

**Files:**
- Modify: `src/app/core/services/api.service.ts:72`
- Modify: `src/environments/environment.prod.ts`
- Modify: `angular.json` (production configuration)

- [ ] **Step 1: Use the environment value in `ApiService`**

Change line 72 from:
```typescript
  private readonly apiUrl = 'http://localhost:5201/api';
```
to:
```typescript
  private readonly apiUrl = environment.apiUrl;
```
And add at the top of the file (after existing imports):
```typescript
import { environment } from '../../../environments/environment';
```

- [ ] **Step 2: Set the production API URL to relative `/api`**

Replace `src/environments/environment.prod.ts` with:
```typescript
export const environment = {
  production: true,
  apiUrl: '/api'
};
```

- [ ] **Step 3: Keep dev pointing at the local API**

Replace `src/environments/environment.ts` with:
```typescript
export const environment = {
  production: false,
  apiUrl: 'http://localhost:5201/api'
};
```

- [ ] **Step 4: Add `fileReplacements` to the production build config**

In `angular.json`, inside `architect.build.configurations.production` (the object starting at line 37), add a `fileReplacements` array as the first key:
```json
"fileReplacements": [
  {
    "replace": "src/environments/environment.ts",
    "with": "src/environments/environment.prod.ts"
  }
],
```

- [ ] **Step 5: Verify the production build succeeds and emits the relative URL**

Run: `cd ~/source/repos/SaaSBasePlatform-Angular && npm run build:prod`
Expected: build completes; output in `dist/saas-baseplatform-erp`.

Run: `grep -rl "/api" dist/saas-baseplatform-erp/*.js >/dev/null && echo "relative api present"`
Expected: `relative api present`

- [ ] **Step 6: Commit**

```bash
cd ~/source/repos/SaaSBasePlatform-Angular
git checkout -b ci/containerize
git add src/app/core/services/api.service.ts src/environments/environment.ts src/environments/environment.prod.ts angular.json
git commit -m "feat: drive API base URL from environment; relative /api in prod"
```

### Task 18: Frontend Dockerfile, nginx config, .dockerignore, build workflow

**Files:**
- Create: `~/source/repos/SaaSBasePlatform-Angular/Dockerfile`
- Create: `~/source/repos/SaaSBasePlatform-Angular/nginx/default.conf.template`
- Create: `~/source/repos/SaaSBasePlatform-Angular/.dockerignore`
- Create: `~/source/repos/SaaSBasePlatform-Angular/.github/workflows/build-and-deploy.yml`

- [ ] **Step 1: Write `nginx/default.conf.template`**

The official nginx image runs `envsubst` over `/etc/nginx/templates/*.template` into
`/etc/nginx/conf.d/` at startup, substituting `${API_URL}`.

```nginx
server {
    listen 8080;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location /api/ {
        proxy_pass ${API_URL}/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

- [ ] **Step 2: Write `Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1
FROM node:20-alpine AS build
WORKDIR /src
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build:prod

FROM nginx:1.27-alpine AS final
ENV API_URL=http://localhost:5201
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/dist/saas-baseplatform-erp /usr/share/nginx/html
EXPOSE 8080
```

- [ ] **Step 3: Write `.dockerignore`**

```gitignore
node_modules/
dist/
.angular/
.git/
docs/
**/*.spec.ts
```

- [ ] **Step 4: Build to verify**

Run: `cd ~/source/repos/SaaSBasePlatform-Angular && docker build -t saasbase-web:test .`
Expected: build completes successfully.

- [ ] **Step 5: Smoke-test the container serves the SPA**

Run:
```bash
docker run -d --rm -p 8081:8080 -e API_URL=http://example.invalid --name web-test saasbase-web:test
sleep 2
curl -sf http://localhost:8081/ | grep -qi "<app-root" && echo "spa served"
docker rm -f web-test
```
Expected: `spa served`

- [ ] **Step 6: Write `.github/workflows/build-and-deploy.yml`**

```yaml
name: build-and-deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: ACR login
        run: az acr login --name "${{ secrets.ACR_LOGIN_SERVER }}"

      - name: Build and push
        run: |
          IMAGE="${{ secrets.ACR_LOGIN_SERVER }}/saasbase-web"
          docker build -t "$IMAGE:${{ github.sha }}" -t "$IMAGE:latest" .
          docker push "$IMAGE:${{ github.sha }}"
          docker push "$IMAGE:latest"

      - name: Dispatch deploy
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.DISPATCH_TOKEN }}
          repository: nickolascheidt/SaaSBasePlatform-DevOps
          event-type: deploy
          client-payload: '{"app":"web","image_tag":"${{ github.sha }}","sha":"${{ github.sha }}"}'
```

- [ ] **Step 7: Validate YAML and commit**

Run: `python -c "import yaml; yaml.safe_load(open('.github/workflows/build-and-deploy.yml')); print('ok')"`
Expected: `ok`

```bash
git add Dockerfile nginx/default.conf.template .dockerignore .github/workflows/build-and-deploy.yml
git commit -m "ci: containerize SPA with nginx and add build+deploy workflow"
```

---

## Final integration verification

After all tasks and the one-time bootstrap (RUNBOOK §1):

- [ ] Apply `terraform/core` once; confirm ACR exists and both app SPs have AcrPush.
- [ ] Push a trivial change to `SaaSBasePlatform` `main`; confirm the image lands in ACR and `dev` API revision updates (`az containerapp revision list -n ca-api-dev -g rg-saasbase-dev`).
- [ ] Push a change to `SaaSBasePlatform-Angular` `main`; confirm `ca-web-dev` updates and the SPA loads, with `/api/auth/login` reaching the API (check browser network tab → same-origin `/api`).
- [ ] Run the orchestrator `deploy` workflow manually with `env=prod`; confirm the `prod` environment approval gate fires before apply.
- [ ] Verify the API resolves Key Vault secrets (no startup error about `JWT Key not configured`; `/health/ready` returns healthy).

---

## Self-review notes (addressed)

- **Spec coverage:** Azure target, Terraform, Container Apps (API + nginx web), managed Postgres + Redis, Key Vault, dev/prod, OIDC, shared ACR, repository_dispatch trigger, app-repo Dockerfiles + CI — all have tasks.
- **Connection-string keys** verified against `SaaSBasePlatform` appsettings: `ConnectionStrings:DefaultConnection`, `ConnectionStrings:Redis`, `Jwt:Key/Issuer/Audience`; double-underscore env forms used. Health paths `/health/live` + `/health/ready` confirmed in `HealthChecksConfiguration.cs`.
- **Frontend** verified: `:browser` builder → `dist/saas-baseplatform-erp` (no `/browser`); `ApiService` hardcoding and missing `fileReplacements` are both fixed in Task 17.
- **Cross-reference cycle** between API and web Container Apps is broken by deriving both FQDNs from the Container Apps environment `default_domain` (Task 10, Steps 3a–3b).
- **Type/name consistency:** image repos `saasbase-api` / `saasbase-web`, env var/secret names, and module output names are consistent across Terraform, workflows, and the contract doc.

---

## Implementation notes (deviations applied during execution)

Made while implementing/validating and after an independent code review. The shipped code reflects these; the task bodies above show the original plan.

1. **Key Vault `for_each`** uses `nonsensitive(toset(keys(var.secrets)))` (not `var.secrets`) — Terraform rejects a sensitive value as a `for_each` argument. Secret names are non-sensitive; values stay sensitive.
2. **Container Apps identity** is a **user-assigned identity** (`azurerm_user_assigned_identity.apps`), not system-assigned. Its `AcrPull` + `Key Vault Secrets User` grants are created before the apps, with a `time_sleep` for RBAC propagation, so the first `terraform apply` resolves the Key Vault secret references. The container-app module takes `identity_id` instead of `acr_id`, and no longer emits `principal_id` or creates its own role assignment.
3. **Per-env image tag files** are `images.dev.tfvars.json` / `images.prod.tfvars.json` (NOT `*.auto.tfvars.json`), passed via `-var-file`. Auto-loaded `*.auto.tfvars.json` files all load together regardless of env, letting prod tags override dev. No `images.auto.tfvars.json` copy step.
4. **`deploy.yml`** adds a per-env `concurrency` group, checks out `ref: main`, uses an explicit empty-diff check, and `git pull --rebase` + `git push origin HEAD:main` to avoid concurrent-dispatch races.
5. **nginx template** uses a variable upstream (`set $upstream ${API_URL}; proxy_pass $upstream;`) with a `resolver` (request-time DNS so the container starts before the API is resolvable), plus `proxy_ssl_server_name on` and `Host ${API_HOST}` for Azure Container Apps HTTPS/Host routing. The web container receives both `API_URL` and `API_HOST`.
6. **Web container** has a readiness probe on `/`.
7. **`.gitattributes`** (LF enforcement) and a top-level **`.gitignore`** (ignoring `**/.terraform/`, state, module lock files) were added; only the two root `.terraform.lock.hcl` files are tracked.

### Known fast-follows (non-blocking)
- Backend `Dockerfile` copies all source before `dotnet restore`, so the restore layer is not cached across source-only changes (CI speed only).
- App-repo workflows have no path filter / `concurrency` guard.
- First `terraform apply` may still need a single re-run if Azure RBAC propagation exceeds the 60s wait.
