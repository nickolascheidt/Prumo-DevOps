# App-repo → Orchestrator contract

Each app repo builds one image, pushes it to the shared ACR by commit SHA, then
dispatches a deploy event.

## Image names
- Backend: `<acr>.azurecr.io/saasbase-api:<git-sha>` (also `:latest`)
- Frontend: `<acr>.azurecr.io/saasbase-web:<git-sha>` (also `:latest`)

## repository_dispatch payload
Sent to `nickolascheidt/SaaSBasePlatform-DevOps`:

```json
{
  "event_type": "deploy",
  "client_payload": { "app": "api", "image_tag": "<git-sha>", "sha": "<git-sha>" }
}
```
`app` is `api` (backend) or `web` (frontend). Dispatches always deploy to **dev**.
Production is deployed manually via the orchestrator's `deploy` workflow (`workflow_dispatch`).

## Secrets the app repos need
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — OIDC login for ACR push.
- `ACR_LOGIN_SERVER` — e.g. `acrsaasbasecore.azurecr.io`.
- `DISPATCH_TOKEN` — fine-grained PAT with `contents:write` (or repo) on the orchestrator repo,
  used to send the repository_dispatch.
