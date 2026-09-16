# SaaSBasePlatform-DevOps

Infraestrutura e deploy do Prumo: Terraform para a AWS e GitHub Actions para construir as
imagens da API .NET e da SPA Angular.

O alvo é o **piloto**: uma instância Lightsail de 2 GB em `sa-east-1` rodando
`docker compose` — Caddy (TLS), o nginx do Angular, a API e o Postgres — com snapshot
diário, por ~US$ 14/mês. Não é ambiente descartável; é a versão que vai à frente de
cliente.

**Nada está aplicado. Nenhum recurso existe na AWS. Custo US$ 0,00.** O que falta é
trabalho de conta, não de código, e está listado no `NEXT_SESSION.md` (untracked) e no
plano, no repo da aplicação.

- Desenho: `SaaSBasePlatform/docs/superpowers/specs/2026-09-07-aws-dev-environment-design.md`
- Plano, 13 tasks: `SaaSBasePlatform/docs/superpowers/plans/2026-09-07-aws-dev-environment.md`
- Arquitetura: `docs/ARCHITECTURE.md`
- Contrato com os repos de aplicação: `docs/CONTRACT.md`
- Operação: `docs/RUNBOOK.md`

## Layout
- `terraform/aws/dev` — a stack inteira do piloto, num diretório só: ECR, SQS, a instância
  Lightsail, o IP estático, a role de OIDC e o usuário de runtime.
- `deploy/` — `docker-compose.yml`, `Caddyfile`, `db/roles.sql` e o `deploy.sh`, que sobe
  tudo por SSH a partir da **sua** máquina.
- `scripts/aws` — `bootstrap-dev.sh` (tasks 1 e 2) e `gen-secrets.sh` (task 3).
- `.github/workflows` — `infra-check`, que roda `fmt`/`validate` offline em PR.

## História

A infraestrutura viveu na Azure — Container Apps, ACR, Key Vault, PostgreSQL Flexible
Server — e funcionou ponta a ponta antes de ser derrubada para US$ 0. **A árvore `azurerm`
foi removida em 2026-09-16**, junto com os workflows e os scripts de `az`. O desenho e o
plano daquela época continuam em `docs/superpowers/`, como registro.

O `rg-saasbase-tfstate` **ainda existe na Azure**, custando centavos, e agora sem código
que o gerencie: derrubar é trabalho manual no portal, quando quiser.
