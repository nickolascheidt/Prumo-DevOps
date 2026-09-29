#!/usr/bin/env bash
#
# Brings up the dev stack on AWS:
#
#   1. the S3 state bucket (versioned, no public access), named after the account
#   2. `terraform init` against it
#   3. `terraform plan` of the whole stack, then apply after asking
#
# Refuses to run with root credentials: the state bucket would be born owned by root.
# Idempotent: running it again does not duplicate anything.
#
# Usage:
#   scripts/aws/bootstrap-dev.sh              # plan, show, ask, apply
#   scripts/aws/bootstrap-dev.sh --plan-only  # stop after the plan
#   scripts/aws/bootstrap-dev.sh --yes        # apply without asking
#
# SSH to the host is allowed only from SSH_ALLOWED_CIDR, which defaults to your current
# public IP (/32).

set -euo pipefail

REGION="sa-east-1"
ASSUME_YES=0
PLAN_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y)    ASSUME_YES=1 ;;
    --plan-only) PLAN_ONLY=1 ;;
    -h|--help)   sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    [ok] %s\n' "$*"; }
warn() { printf '    [!]  %s\n' "$*"; }
die()  { printf '\n[FAILED] %s\n' "$*" >&2; exit 1; }

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform/aws/dev" && pwd)"
[ -f "$TF_DIR/versions.tf" ] || die "Could not find $TF_DIR/versions.tf. Run it from the repo."

# ---------------------------------------------------------------------- tools
step "Local tools"

command -v aws       >/dev/null || die "The AWS CLI is not on the PATH."
command -v terraform >/dev/null || die "Terraform is not on the PATH."
command -v curl      >/dev/null || die "curl is not on the PATH."
ok "aws $(aws --version 2>&1 | sed 's|aws-cli/||;s| .*||')"

TF_VER="$(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$TF_VER" ] || TF_VER="$(terraform version | head -1 | sed 's/^Terraform v//')"
if [ "$(printf '%s\n1.10.0\n' "$TF_VER" | sort -V | head -1)" != "1.10.0" ]; then
  die "Terraform $TF_VER is too old. Native S3 locking (use_lockfile) needs 1.10+."
fi
ok "terraform $TF_VER"

[ -f "$HOME/.ssh/prumo-dev.pub" ] || die "No SSH key for the host. Create it with:
    ssh-keygen -t ed25519 -f ~/.ssh/prumo-dev"
ok "ssh key ~/.ssh/prumo-dev.pub"

# ----------------------------------------------------------------- credential
step "Credential"

IDENTITY="$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1)" || {
  printf '%s\n' "$IDENTITY" >&2
  die "No credential. Configure an IAM user (not root) with: aws configure"
}
read -r ACCOUNT ARN <<< "$IDENTITY"

case "$ARN" in
  *:root)
    die "This ARN belongs to the ROOT account: $ARN
    Use an IAM user with MFA instead; the state bucket must not be owned by root." ;;
esac
ok "$ARN"

BUDGETS="$(aws budgets describe-budgets --account-id "$ACCOUNT" --max-results 1 \
  --query 'Budgets[0].BudgetName' --output text 2>/dev/null || echo ERROR)"
if [ "$BUDGETS" = "None" ] || [ "$BUDGETS" = "ERROR" ] || [ -z "$BUDGETS" ]; then
  warn "No budget alarm found in this account (or no permission to read it)."
  warn "Create one before applying: it is the only warning between a mistake and a bill."
else
  ok "budget alarm: $BUDGETS"
fi

# ---------------------------------------------------------------- state bucket
BUCKET="prumo-tfstate-$ACCOUNT"
step "State bucket $BUCKET"

if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1; then
  ok "already exists"
else
  # --create-bucket-configuration is mandatory outside us-east-1: without it AWS
  # answers IllegalLocationConstraintException.
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  ok "created"
fi

# Both PUTs are idempotent on purpose: running them every time fixes a bucket someone
# changed by hand.
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" --region "$REGION" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$BUCKET" --region "$REGION" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

VERSIONING="$(aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
  --query Status --output text 2>/dev/null || echo None)"
[ "$VERSIONING" = "Enabled" ] || die "Bucket versioning is '$VERSIONING'.
    It is not optional: it is what allows going back from a corrupted state."
ok "versioning on, public access blocked"

# ------------------------------------------------------------------------ init
step "terraform init"

cd "$TF_DIR"
# The bucket is partial backend configuration, so no account ID is committed.
# -reconfigure because `init -backend=false` may have run before (CI, local checks);
# without it Terraform asks about migrating state and hangs on a prompt.
terraform init -input=false -reconfigure -backend-config="bucket=$BUCKET"
terraform validate
ok "backend initialized, configuration valid"

# ------------------------------------------------------------------ plan/apply
step "terraform plan"

SSH_ALLOWED_CIDR="${SSH_ALLOWED_CIDR:-$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')/32}"
ok "SSH allowed from $SSH_ALLOWED_CIDR"

PLAN_FILE="$(mktemp -t prumo-plan.XXXXXX)"
trap 'rm -f "$PLAN_FILE"' EXIT

terraform plan -input=false -out="$PLAN_FILE" -var "ssh_allowed_cidr=$SSH_ALLOWED_CIDR"

echo
echo "    Applying starts the fixed cost: the Lightsail instance and its static IP"
echo "    (about US\$ 12/month), plus ECR storage and snapshots."

if [ "$PLAN_ONLY" -eq 1 ]; then
  echo
  ok "--plan-only: stopping before the apply."
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  echo
  read -r -p "    Apply? [y/N] " ANSWER
  case "$ANSWER" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "    Aborted. Nothing was applied."; exit 0 ;;
  esac
fi

terraform apply -input=false "$PLAN_FILE"

# ------------------------------------------------------------------------ next
step "Done. Next steps (docs/RUNBOOK.md)"

echo
terraform output
cat <<'NEXT'

  1. Create the host's runtime key and keep it for the .env:
         aws iam create-access-key --user-name prumo-dev-box

  2. Generate the secrets and write /opt/prumo/.env on the host from
     deploy/.env.example:
         scripts/aws/gen-secrets.sh

  3. Set AWS_DEPLOY_ROLE_ARN and ECR_REGISTRY in the application repos, from the
     outputs above.

  4. Deploy:
         deploy/deploy.sh

NEXT
