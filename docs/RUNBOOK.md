# Runbook

> This was never executed against a real account. It is the procedure the design implies.

## Before anything costs money

1. Work as an IAM user with console access and MFA, **not the root account**.
   `scripts/aws/bootstrap-dev.sh` refuses to run with root credentials: the state bucket
   would be born owned by root.
2. Create a **budget alarm** (for example US$ 40/month, alerts at 50% and 100%). With no
   credits and no free tier, it is the only warning between a mistake and a bill.
3. `aws configure` with that user's key, region `sa-east-1`.
4. An SSH key pair for the host: `ssh-keygen -t ed25519 -f ~/.ssh/prumo-dev`.

## Bootstrap

```bash
scripts/aws/bootstrap-dev.sh --plan-only   # drop the flag to apply
```

It creates the state bucket (versioned, public access blocked), runs `terraform init`
against it and plans the whole stack. It is idempotent. `ssh_allowed_cidr` defaults to your
current public IP (`SSH_ALLOWED_CIDR` overrides it). **The apply is where the
~US$ 14/month starts.**

Then, once:

1. The runtime key for the host: `aws iam create-access-key --user-name prumo-dev-box`.
2. The `.env` on the instance: start from `deploy/.env.example`, fill it with
   `scripts/aws/gen-secrets.sh`, the runtime key and the `terraform output` values, and
   copy it to `/opt/prumo/.env` on the host. Keep a copy in a password manager; it is not
   stored anywhere else.
3. The two GitHub secrets in the application repos (see [CONTRACT.md](CONTRACT.md)), and
   switch their image workflows from `workflow_dispatch` to `push`.

Without a domain of your own, use the `sslip_domain` output (the static IP with dashes,
for example `54-207-1-2.sslip.io`) as `DOMAIN`: it resolves by itself and Caddy gets a real
certificate for it.

## Deploy

```bash
deploy/deploy.sh          # :latest images
deploy/deploy.sh <sha>    # pin a version of both images
```

It copies `docker-compose.yml`, `Caddyfile` and `db/` to the host over SSH, sets the image
tags in the host's `.env` and brings the stack up.

## Rollback

`deploy/deploy.sh <previous-sha>`. Old images stay in ECR until the lifecycle policy keeps
only the last 10.

## Migrations

The deploy has no migration step: on the host the API starts with
`Database__MigrateOnStartup=true`, over a separate connection with the migrator
credential. That is the piece to replace if the compute changes. Locally the rule is the
opposite — the API never migrates itself, and `dotnet ef database update` is manual.

## Configuration that has to match the API

- `ConnectionStrings__DefaultConnection` and `ConnectionStrings__MigratorConnection`
- `Jwt__Key` — **without it the API refuses to start, on purpose**
- `AllowedHosts` and the nginx `API_HOST`, both the public domain: nginx forwards the
  `Host` header and the API does host filtering. A mismatch returns 400 on every call.
- `Seed__AdminPassword` — the first sign-in
