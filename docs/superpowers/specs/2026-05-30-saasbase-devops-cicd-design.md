# SaaSBasePlatform-DevOps — CI/CD Orchestration Design

**Date:** 2026-05-30
**Status:** Approved (design)
**Repo:** `nickolascheidt/SaaSBasePlatform-DevOps`

## 1. Purpose

A dedicated orchestration repository that owns **all Azure infrastructure** (Terraform)
and **all deployment** (GitHub Actions) for the SaaS Base Platform. The two application
repositories build and publish their own container images and notify this repo to deploy.

### Source repositories (the things being deployed)

- **Backend** — `nickolascheidt/SaaSBasePlatform`
  - .NET 10 / ASP.NET Core, Clean Architecture.
  - Runs EF Core migrations + seeders on startup (`app.InitializeDatabaseAsync()`).
  - Depends on **PostgreSQL** and **Redis**.
  - Exposes health checks (`HealthChecksConfiguration`).
  - No Dockerfile or CI yet.
- **Frontend** — `nickolascheidt/SaaSBasePlatform-Angular`
  - Angular 18 SPA, builds to static files (`npm run build:prod`).
  - Dev API base URL hardcoded to `http://localhost:5201/api` in `ApiService`.
  - No Dockerfile or CI yet.

## 2. Key decisions

| Decision | Choice |
|----------|--------|
| Cloud target | **Azure** |
| IaC tool | **Terraform** (remote state in Azure Storage) |
| API hosting | **Azure Container Apps** |
| Frontend hosting | **Azure Container Apps** (nginx container serving the SPA) |
| Data services | **Managed** — Azure Database for PostgreSQL Flexible Server + Azure Cache for Redis |
| Environments | **dev** (auto from `main`) + **prod** (manual approval) |
| Repo model | Orchestrator owns infra + deploy; app repos build & push their own images |
| Cross-repo trigger | **`repository_dispatch`** with image tag payload |
| App-repo changes | **In scope** — add Dockerfile + build-and-deploy workflow to both app repos |
| Cloud auth | GitHub Actions → Azure via **OIDC federated credentials** (no stored secrets) |
| Image tag scheme | App repo git **commit SHA** (immutable); `latest` also updated |
| Container registry | **One shared ACR** (not per-env) |

## 3. Architecture

```
SaaSBasePlatform (.NET)  ──build+push image──▶ ACR ──┐
                          └─repository_dispatch──────┤
SaaSBasePlatform-Angular ──build+push image──▶ ACR ──┤
                          └─repository_dispatch──────┤
                                                     ▼
                              SaaSBasePlatform-DevOps (this repo)
                              Terraform (infra) + deploy workflow
                                                     ▼
                                   Azure: dev  /  prod
```

### Azure topology (per environment: `dev`, `prod`)

- **Resource group** `rg-saasbase-<env>`
- **Azure Container Registry** — one shared instance in a core resource group
- **Container Apps Environment** hosting:
  - `ca-api-<env>` — the .NET API (external ingress)
  - `ca-web-<env>` — nginx serving the Angular SPA (external ingress), proxying `/api` → API
- **Azure Database for PostgreSQL Flexible Server** `psql-saasbase-<env>`
- **Azure Cache for Redis** `redis-saasbase-<env>`
- **Key Vault** `kv-saasbase-<env>` — JWT signing key, DB password, Redis key; Container Apps
  read secrets via managed identity
- **Log Analytics workspace** — Container Apps logs

## 4. Repository layout

```
SaaSBasePlatform-DevOps/
├── terraform/
│   ├── modules/            # acr, container-app-env, container-app, postgres, redis, keyvault
│   ├── core/               # shared ACR + state-related resources
│   └── envs/
│       ├── dev/            # backend config + dev.tfvars
│       └── prod/
├── .github/workflows/
│   ├── deploy.yml          # repository_dispatch + workflow_dispatch → terraform apply + revision update
│   ├── infra-plan.yml      # PR plan on terraform changes
│   └── infra-bootstrap.yml # one-time: state storage account, ACR, OIDC app reg (documented)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── CONTRACT.md         # dispatch payload + image tag scheme the app repos must honor
│   └── RUNBOOK.md          # bootstrap, secrets, manual deploy, rollback
└── README.md
```

## 5. CI/CD flow

- **Auth:** GitHub Actions authenticates to Azure via OIDC federated credentials. No
  long-lived secrets in either repo. Terraform state lives in an Azure Storage backend.
- **Image tag:** the git commit SHA of the app repo (immutable); `latest` is also moved.
- **App-repo workflow** (added to both repos): on push to `main` → build multi-stage image
  → push to ACR `…:<sha>` → send `repository_dispatch`
  (`event_type: deploy`, payload `{ app, image_tag, sha }`).
- **Orchestrator `deploy.yml`:** receives the dispatch (or manual `workflow_dispatch`) →
  resolves the target environment (dispatch from app `main` → **dev** automatically; **prod**
  requires a GitHub **Environment** approval) → `terraform apply` with the new image tag →
  Container App revision rolls over. The other app keeps its currently deployed tag (stored
  in state / as a tfvar).

## 6. Error handling, testing, rollback

- **Terraform:** PR `plan` gate; `apply` only on `main` / dispatch. State locking via the
  Azure backend.
- **Deploy safety:** Container Apps keep the previous revision; a failed health check keeps
  traffic on the old revision. **Rollback** = re-dispatch / `workflow_dispatch` with a
  previous SHA.
- **Validation:** `terraform fmt -check` + `terraform validate` in CI. Health probes wired
  to the API's existing health-check endpoint.
- **Secrets:** never in tfvars — Key Vault references + GitHub OIDC only.

## 7. App-repo additions (in scope)

- **.NET** (`SaaSBasePlatform`): multi-stage `Dockerfile` (`dotnet publish` → `aspnet:10`
  runtime), `.dockerignore`, `build-and-deploy.yml`. Migrations already run on startup, so
  no separate migration step.
- **Angular** (`SaaSBasePlatform-Angular`): multi-stage `Dockerfile` (`npm run build:prod`
  → nginx), nginx config proxying `/api` → API container, `.dockerignore`,
  `build-and-deploy.yml`. The hardcoded `localhost:5201` is dev-only; in containers the SPA
  reaches the API via the `/api` nginx proxy.

## 8. Assumptions

- Single shared ACR (cost-saving) rather than per-environment.
- Bootstrap (state storage account, OIDC app registration, initial RG/ACR) is a documented
  one-time manual/scripted step, not run on every deploy.
- `dev` auto-deploys from `main`; `prod` is gated by a GitHub Environment approval.
- The API's existing startup migrations are acceptable for deploy (no separate migration job).
