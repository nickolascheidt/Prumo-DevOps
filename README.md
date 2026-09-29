# Prumo — DevOps

[![infra-check](https://github.com/nickolascheidt/Prumo-DevOps/actions/workflows/infra-check.yml/badge.svg)](https://github.com/nickolascheidt/Prumo-DevOps/actions/workflows/infra-check.yml)

*[Leia em português](README.pt-BR.md)*

Infrastructure and deployment for [Prumo](https://github.com/nickolascheidt/Prumo), a
multi-tenant ERP (API in .NET, SPA in [Angular](https://github.com/nickolascheidt/Prumo-Angular)):
Terraform for AWS, a Docker Compose stack for the host, and the scripts that tie them
together.

**Status: designed and validated, never applied.** Every Terraform file passes
`fmt`/`validate` against the real provider (the `infra-check` workflow runs both on pull
requests), but the project stopped before anything was created in an AWS account. This
repo is the design, kept as a portfolio piece.

## The design in one paragraph

One 2 GB Lightsail instance in `sa-east-1` runs four containers with `docker compose`:
Caddy (TLS), the Angular nginx, the API and PostgreSQL 17, with daily snapshots, for about
US$ 14/month. Images live in ECR, pushed by GitHub Actions through an OIDC role (no stored
AWS keys). Deploys are `deploy/deploy.sh` over SSH from a workstation. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the reasoning and the trade-offs.

## Layout

| Path | What it is |
|---|---|
| `terraform/aws/dev` | The whole stack in one root: ECR, the Lightsail instance, static IP, firewall, OIDC deploy role, a runtime IAM user, an optional Route 53 record |
| `deploy/` | `docker-compose.yml`, `Caddyfile`, `db/roles.sql`, `.env.example` and `deploy.sh` |
| `scripts/aws` | `bootstrap-dev.sh` (state bucket, init, plan, apply) and `gen-secrets.sh` |
| `.github/workflows` | `infra-check`: offline `terraform fmt` and `validate` on pull requests |
| `docs/` | [Architecture](docs/ARCHITECTURE.md), [runbook](docs/RUNBOOK.md), [contract with the app repos](docs/CONTRACT.md) |

## History

The first version ran on Azure — Container Apps, ACR, Key Vault, PostgreSQL Flexible
Server — and worked end to end before being torn down. It moved to this AWS design to
trade scale-to-zero pricing for a small fixed bill; the Azure Terraform is still in the git
history.

## License

[MIT](LICENSE)
