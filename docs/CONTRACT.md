# Contract: application repos → this repo

Each application repo builds **one** image and pushes it to ECR, tagged with the commit SHA
and with `latest`. **That is where it stops**: deploying is `deploy/deploy.sh` in this
repo, run from a workstation over SSH.

## Image names

- API: `<ecr-registry>/prumo-api:<git-sha>` (and `:latest`)
- Frontend: `<ecr-registry>/prumo-web:<git-sha>` (and `:latest`)

The registry comes from `terraform output -raw ecr_registry` and looks like
`<account-id>.dkr.ecr.sa-east-1.amazonaws.com`.

## Secrets the application repos need

Two, the same in both repos, both from `terraform output` here:

- `AWS_DEPLOY_ROLE_ARN` — the role assumed through OIDC, from `github_deploy_role_arn`.
  No access key is stored in a secret.
- `ECR_REGISTRY` — from `ecr_registry`.

## Triggers

Both image workflows (`build-and-deploy.yml` in the application repos) run on
**`workflow_dispatch`** on purpose: without the ECR and the secrets, a push trigger would
paint every commit red. Once the stack exists, switch them to:

```yaml
on:
  push:
    branches: [main]
```
