# Runbook

## One-time bootstrap
1. `az login`
2. `LOCATION=brazilsouth bash scripts/bootstrap-state.sh`
3. `bash scripts/bootstrap-oidc.sh` — note the printed client IDs and SP object IDs.
4. In each GitHub repo, add secrets:
   - Orchestrator: `AZURE_CLIENT_ID` (orchestrator), `AZURE_TENANT_ID`,
     `AZURE_SUBSCRIPTION_ID`, `POSTGRES_ADMIN_PASSWORD`, `JWT_KEY`.
   - Backend & Frontend: `AZURE_CLIENT_ID` (their own), `AZURE_TENANT_ID`,
     `AZURE_SUBSCRIPTION_ID`, `ACR_LOGIN_SERVER`, `DISPATCH_TOKEN`.
5. Create GitHub Environments `dev` and `prod` in the orchestrator repo; add required
   reviewers to `prod`.
6. Apply core once to create the ACR and grant AcrPush:
   ```bash
   cd terraform/core
   terraform init
   terraform apply -var 'acr_pusher_object_ids=["<backend-sp-oid>","<frontend-sp-oid>"]'
   ```

## First app deploy
Push to `main` in an app repo → image builds + pushes → dispatch → dev deploys.

## Manual prod deploy
Orchestrator repo → Actions → `deploy` → Run workflow → choose `env=prod`,
`app=api|web`, `image_tag=<sha>`. Approve the `prod` environment gate.

## Rollback
Re-run `deploy` (`workflow_dispatch`) with a previous `image_tag`. Container Apps keep the
prior revision; traffic only shifts after the new revision is healthy.

## Connection-string key reference (must match the API)
- `ConnectionStrings__DefaultConnection` (Npgsql)
- `ConnectionStrings__Redis` (StackExchange.Redis)
- `Jwt__Key`, `Jwt__Issuer`, `Jwt__Audience`
