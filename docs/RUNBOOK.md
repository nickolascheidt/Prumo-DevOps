# Runbook

> **Nada disto foi executado ainda.** Nenhum recurso existe na AWS, o custo é US$ 0,00, e
> o `NEXT_SESSION.md` (untracked) é quem guarda o estado corrente. As 13 tasks numeradas
> vivem no plano, em
> `SaaSBasePlatform/docs/superpowers/plans/2026-09-07-aws-dev-environment.md`.

## O portão: Task 0

Trabalho humano no console da AWS, conta `767397939785`, e **nada que gasta dinheiro
começa antes**:

1. Acesso ao console + MFA no usuário IAM `nickolas` (hoje ele só tem chave programática,
   e por isso o dia a dia acontece no root).
2. Rotacionar a chave de acesso de 448 dias e apagar a antiga.
3. `aws configure` com a chave nova, região `sa-east-1`.
4. **Budget alarm de US$ 40/mês, com alerta em 50% e 100%.** A conta não tem crédito
   nenhum e o free tier expirou: esse alarme é o único aviso entre um erro e uma fatura.

O portão é `aws sts get-caller-identity` devolver um ARN que **não** termine em `:root`.
Antes disso, o bucket de estado nasceria com credencial de root — exatamente o que a
Task 0 existe para evitar.

## Bootstrap, uma vez

```bash
scripts/aws/bootstrap-dev.sh --plan-only   # tire a flag para aplicar
scripts/aws/gen-secrets.sh                 # Task 3: gera o .env
```

O primeiro cobre as tasks 1 e 2 e recusa andar se a Task 0 não estiver feita; é
idempotente. O `apply` da Task 2 cria **9** recursos, não os 6 que o plano diz — o
`oidc.tf` da Task 4 mora na mesma árvore e sobe junto.

Criar o bucket de estado é o único passo de CLI que sobra fora do script:
`--create-bucket-configuration LocationConstraint=sa-east-1` é obrigatório fora de
`us-east-1`.

## A máquina

`terraform apply` na Task 5 — **é aqui que os ~US$ 14/mês começam.** Depois dele, em
ordem: o par SSH (`ssh-keygen -t ed25519 -f ~/.ssh/prumo-dev`), a chave do usuário de
runtime (`aws iam create-access-key --user-name prumo-dev-box`), o `.env` na instância
(Task 7, Passo 4), `ssh_allowed_cidr` apontando para o seu IP, os dois secrets do GitHub e
a virada dos dois workflows de `workflow_dispatch` para `push`.

## Deploy

```bash
deploy/deploy.sh          # imagens :latest
deploy/deploy.sh <sha>    # fixa uma versão
```

Roda da **sua** máquina, não do CI, e precisa de `~/.ssh/prumo-dev`. Ele leva
`docker-compose.yml`, `Caddyfile` e `db/` por SSH, ajusta as tags no `.env` da instância e
sobe a stack.

## Rollback

`deploy/deploy.sh <sha-anterior>`. As imagens antigas continuam no ECR até a lifecycle
policy as recolher.

## Migrations

O deploy **não tem passo de migration**: no piloto a API sobe com
`Database__MigrateOnStartup=true`, o que é a peça a substituir quando o compute mudar.
Localmente a regra continua sendo outra — a API não migra sozinha, e `dotnet ef database
update` é manual.

## Chaves de configuração que precisam bater com a API

- `ConnectionStrings__DefaultConnection` e `ConnectionStrings__MigratorConnection` (Npgsql)
- `Jwt__Key` — **sem ela a API se recusa a subir, de propósito**
- `Jwt__Issuer`, `Jwt__Audience`
- `AllowedHosts` e `API_HOST`, ambos o domínio público: o nginx repassa o `Host`, e a API
  faz host filtering. Divergência aqui devolve 400 em toda chamada.
- `Sqs__QueueUrl`, `Sqs__Region`. **`Sqs__ServiceUrl` fica ausente**: preenchida, ela
  aponta o SDK para o emulador local, e a guarda de startup recusa.
- `Seed__AdminPassword`
