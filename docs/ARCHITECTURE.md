# Architecture

## The shape

**One machine.** A 2 GB Lightsail instance in `sa-east-1` runs four containers with
`docker compose`:

- **Caddy** — terminates TLS and is the only container that publishes ports (80 and 443).
  It obtains and renews its certificate by itself.
- **nginx** (the Angular image) — serves the SPA and proxies `/api` to the API on the same
  origin, so there is no CORS to configure. It listens on **8080**, which is where Caddy
  points.
- **API** (.NET) — port 8080, **not published** outside the compose network. Runs with
  `ASPNETCORE_ENVIRONMENT=Production`.
- **PostgreSQL 17** — on the same host, with a volume. `db/roles.sql` creates `prumo_app`
  (DML only) and `prumo_migrator` on a new volume, the same as in local development.

Managed outside the machine: **ECR** (two repositories, `prumo-api` and `prumo-web`, with a
lifecycle policy that keeps the last 10 images) and a **static IP**.

## Why this shape

The Azure version ran on Container Apps, which scales to zero and charges for cold starts.
Here the bill is fixed and small (about US$ 14/month), and PostgreSQL on the same host
avoids the price floor of a managed database. It is the right shape for a pilot that has
to stay up and be shown, not for scale. What it gives up, deliberately:

- **No high availability.** One instance; recovery is a daily snapshot (seven kept).
- **SSH instead of SSM.** Lightsail is not reachable by SSM Run Command, so deploys go
  over SSH from a workstation. Port 22 is open only to `ssh_allowed_cidr`, which has no
  default, so Terraform asks instead of silently opening it to the world.
- **A key on disk.** Lightsail has no instance profile, so the host pulls images with the
  access key of a dedicated IAM user whose only right is reading these two ECR
  repositories. The key is created by hand, never by Terraform, so it never lands in the
  state file.

## Secrets

There is no Key Vault or Secrets Manager: the `.env` on the machine is the source, written
once from `deploy/.env.example` and `scripts/aws/gen-secrets.sh`. The JWT key, the database
passwords and the seeded admin password come from there. **The API refuses to start
without `Jwt__Key`** — no configuration overlay in the application repo commits one.

## CI/CD

- The application repos build their images and push them to ECR, assuming
  `github_deploy_role_arn` through GitHub OIDC. The role can push to the two repositories
  and nothing else. See [CONTRACT.md](CONTRACT.md).
- This repo's `infra-check` workflow runs `terraform fmt -check` and
  `terraform init -backend=false && terraform validate` on pull requests, with no
  credentials.

## Terraform state

S3 backend with native locking (`use_lockfile`, Terraform 1.10+). The bucket is
`prumo-tfstate-<account-id>`, versioned and with public access blocked; it is created by
`scripts/aws/bootstrap-dev.sh` and passed to `terraform init` as partial backend
configuration, so no account ID is committed.
