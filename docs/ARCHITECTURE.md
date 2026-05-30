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
