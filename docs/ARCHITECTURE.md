# Arquitetura

Desenho completo em
`SaaSBasePlatform/docs/superpowers/specs/2026-09-07-aws-dev-environment-design.md`.

## A forma

**Uma máquina só.** Uma instância Lightsail de 2 GB em `sa-east-1` roda os quatro
containers por `docker compose`:

- **Caddy** — termina o TLS e é o único que publica porta para o mundo (80 e 443). Obtém e
  renova o certificado sozinho.
- **nginx** (imagem do Angular) — serve a SPA e faz proxy de `/api` para a API, na mesma
  origem, o que dispensa CORS. Escuta em **8080**, não em 80; o Caddy aponta para lá.
- **API** (.NET) — porta 8080, **não publicada** fora da rede do compose. Roda com
  `ASPNETCORE_ENVIRONMENT=Production`.
- **Postgres 17** — no mesmo host, com volume. `db/roles.sql` cria `prumo_app` e
  `prumo_migrator` em volume novo, igual ao ambiente local.

O que é gerenciado fora da máquina: **ECR** (dois repositórios, `prumo-api` e `prumo-web`,
com lifecycle policy), **SQS** (a fila de notificações e sua DLQ) e um **IP estático**.

## Por que assim

Container Apps escalava a zero e cobrava frio; aqui a conta é fixa e pequena (~US$ 14/mês),
e o Postgres no mesmo host evita o piso de preço de um RDS. É o desenho certo para um
piloto que precisa ficar de pé e ser mostrado, não para escala.

## Segredos

Não há Key Vault nem Secrets Manager: o `.env` na máquina é a fonte, escrito uma vez pela
Task 7 e gerado pelo `scripts/aws/gen-secrets.sh`. `Jwt__Key`, as senhas do Postgres e a
`Seed__AdminPassword` entram por ali. **A API recusa subir sem `Jwt__Key`** — nenhum
overlay do repo commita chave.

A credencial do SDK da AWS na máquina é a chave escopada do usuário `prumo-dev-box`: o
Lightsail não tem instance profile, então ela também vem do `.env`.

## Estado do Terraform

Backend S3, bucket `prumo-tfstate-767397939785`, chave `aws/dev.tfstate`, região
`sa-east-1`, com locking nativo (`use_lockfile`, que exige Terraform >= 1.10). **O bucket
ainda não existe** — criá-lo é o Passo 1 da Task 1.

## Antes disto

A stack viveu na Azure (Container Apps, ACR, Key Vault, PostgreSQL Flexible Server) e
funcionou ponta a ponta. A árvore `azurerm` saiu do repo em 2026-09-16; o desenho daquela
época está em `docs/superpowers/specs/2026-05-30-saasbase-devops-cicd-design.md`. O
`rg-saasbase-tfstate` continua de pé na Azure, agora sem código que o gerencie.
