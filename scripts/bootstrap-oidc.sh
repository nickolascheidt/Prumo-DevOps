#!/usr/bin/env bash
# Creates Entra app registrations + GitHub OIDC federated credentials.
# Run once. Requires: az login with permission to create app registrations and assign roles.
set -euo pipefail

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
GH_OWNER="nickolascheidt"
ORCHESTRATOR_REPO="SaaSBasePlatform-DevOps"
BACKEND_REPO="SaaSBasePlatform"
FRONTEND_REPO="SaaSBasePlatform-Angular"

create_app() {
  local name="$1"
  local app_id
  app_id="$(az ad app create --display-name "$name" --query appId -o tsv)"
  az ad sp create --id "$app_id" --output none 2>/dev/null || true
  echo "$app_id"
}

add_fed_cred() {
  local app_id="$1" name="$2" subject="$3"
  az ad app federated-credential create --id "$app_id" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none
}

echo "== Orchestrator identity =="
ORCH_APP_ID="$(create_app "gh-${ORCHESTRATOR_REPO}")"
add_fed_cred "$ORCH_APP_ID" "main"        "repo:${GH_OWNER}/${ORCHESTRATOR_REPO}:ref:refs/heads/main"
add_fed_cred "$ORCH_APP_ID" "env-dev"     "repo:${GH_OWNER}/${ORCHESTRATOR_REPO}:environment:dev"
add_fed_cred "$ORCH_APP_ID" "env-prod"    "repo:${GH_OWNER}/${ORCHESTRATOR_REPO}:environment:prod"
ORCH_SP_ID="$(az ad sp show --id "$ORCH_APP_ID" --query id -o tsv)"
az role assignment create --assignee-object-id "$ORCH_SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/subscriptions/${SUBSCRIPTION_ID}" --output none
az role assignment create --assignee-object-id "$ORCH_SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope "/subscriptions/${SUBSCRIPTION_ID}" --output none

echo "== Backend identity =="
BE_APP_ID="$(create_app "gh-${BACKEND_REPO}")"
add_fed_cred "$BE_APP_ID" "main" "repo:${GH_OWNER}/${BACKEND_REPO}:ref:refs/heads/main"

echo "== Frontend identity =="
FE_APP_ID="$(create_app "gh-${FRONTEND_REPO}")"
add_fed_cred "$FE_APP_ID" "main" "repo:${GH_OWNER}/${FRONTEND_REPO}:ref:refs/heads/main"

echo ""
echo "Tenant ID:        $(az account show --query tenantId -o tsv)"
echo "Subscription ID:  $SUBSCRIPTION_ID"
echo "ORCHESTRATOR AZURE_CLIENT_ID: $ORCH_APP_ID"
echo "BACKEND      AZURE_CLIENT_ID: $BE_APP_ID"
echo "FRONTEND     AZURE_CLIENT_ID: $FE_APP_ID"
echo ""
echo "NOTE: AcrPush for backend/frontend SPs is granted by core Terraform (acr_pusher_object_ids)."
echo "Pass these object IDs to core: $(az ad sp show --id "$BE_APP_ID" --query id -o tsv), $(az ad sp show --id "$FE_APP_ID" --query id -o tsv)"
