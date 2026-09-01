# Architecture

See `docs/superpowers/specs/2026-05-30-saasbase-devops-cicd-design.md` for the full design.

- One shared ACR (`rg-saasbase-core`).
- Per env (`dev`, `prod`): resource group `rg-saasbase-<env>` containing a Container Apps
  environment (`ca-api-<env>`, `ca-web-<env>`), PostgreSQL Flexible Server, Key Vault, and
  Log Analytics. No cache: the API's cache abstraction had no consumers, so it and the Redis
  container app were removed. `terraform/modules/redis` is kept but referenced by nothing.
- API reads secrets (`ConnectionStrings__DefaultConnection`, `Jwt__Key`) from Key Vault via
  its managed identity.
- The app containers scale to zero when idle (`min_replicas = 0`), so a parked environment
  costs almost nothing and pays a cold start on the first request instead.
- Web (nginx) serves the SPA and proxies `/api` to the API container.
- Terraform state in `stsaasbasetfstate` (`rg-saasbase-tfstate`), keys `core`, `app-dev`, `app-prod`.
