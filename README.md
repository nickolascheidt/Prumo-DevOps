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
