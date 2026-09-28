#!/usr/bin/env bash
#
# Sobe a fatia do ambiente de dev na AWS que já tem HCL escrito e validado:
#
#   Task 1, Passo 1  — o bucket S3 do estado (versionado, sem acesso público)
#   Task 1, Passo 7  — `terraform init` de verdade, contra o S3
#   Task 2, Passo 4  — apply: ECR e a role de deploy por OIDC (Task 4)
#
# PRÉ-REQUISITO: a Task 0 inteira. Este script RECUSA rodar com credencial de
# raiz — é justamente o que a Task 0 existe para evitar.
#
# Idempotente: rodar de novo não duplica nada. Para antes do apply se você pedir.
#
# Uso:
#   scripts/aws/bootstrap-dev.sh              # plan, mostra, pergunta, aplica
#   scripts/aws/bootstrap-dev.sh --plan-only  # para depois do plan
#   scripts/aws/bootstrap-dev.sh --yes        # aplica sem perguntar

set -euo pipefail

REGION="sa-east-1"
ASSUME_YES=0
PLAN_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y)    ASSUME_YES=1 ;;
    --plan-only) PLAN_ONLY=1 ;;
    -h|--help)   sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    [ok] %s\n' "$*"; }
warn() { printf '    [!]  %s\n' "$*"; }
die()  { printf '\n[FALHOU] %s\n' "$*" >&2; exit 1; }

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform/aws/dev" && pwd)"
[ -f "$TF_DIR/versions.tf" ] || die "Nao achei $TF_DIR/versions.tf. Rode do repo devops."

# O nome do bucket vem do backend em versions.tf, nao de uma constante aqui: assim
# o script e a configuracao nao podem divergir em silencio.
BUCKET="$(sed -n 's/.*bucket *= *"\(prumo-tfstate-[0-9]*\)".*/\1/p' "$TF_DIR/versions.tf" | head -1)"
[ -n "$BUCKET" ] || die "Nao consegui ler o nome do bucket do backend em versions.tf."
EXPECTED_ACCOUNT="${BUCKET##*-}"

# ---------------------------------------------------------------- ferramentas
step "Ferramentas locais"

command -v aws       >/dev/null || die "AWS CLI nao esta no PATH."
command -v terraform >/dev/null || die "Terraform nao esta no PATH."
ok "aws $(aws --version 2>&1 | sed 's|aws-cli/||;s| .*||')"

TF_VER="$(terraform version -json 2>/dev/null | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$TF_VER" ] || TF_VER="$(terraform version | head -1 | sed 's/^Terraform v//')"
if [ "$(printf '%s\n1.10.0\n' "$TF_VER" | sort -V | head -1)" != "1.10.0" ]; then
  die "Terraform $TF_VER e velho demais. O locking nativo do S3 (use_lockfile) exige 1.10+."
fi
ok "terraform $TF_VER"

# ------------------------------------------------------- o portao da Task 0
step "Credencial (o portao da Task 0)"

IDENTITY="$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1)" || {
  printf '%s\n' "$IDENTITY" >&2
  die "Sem credencial. Termine a Task 0 e rode: aws configure   (regiao $REGION)"
}
read -r ACCOUNT ARN <<< "$IDENTITY"

case "$ARN" in
  *:root)
    die "Este ARN e da RAIZ: $ARN
    A Task 0 existe exatamente para impedir isto: o bucket de estado nasceria
    pertencendo a raiz. De acesso de console + MFA ao usuario IAM 'nickolas',
    rotacione a chave de 448 dias e reconfigure a CLI com a chave nova." ;;
esac

[ "$ACCOUNT" = "$EXPECTED_ACCOUNT" ] || die "Conta errada.
    Conectado em      : $ACCOUNT
    versions.tf espera: $EXPECTED_ACCOUNT (pelo nome do bucket $BUCKET)"

ok "$ARN"
ok "conta $ACCOUNT"

CONFIGURED_REGION="$(aws configure get region 2>/dev/null || true)"
if [ "$CONFIGURED_REGION" != "$REGION" ]; then
  warn "A regiao padrao da CLI e '${CONFIGURED_REGION:-<vazia>}', nao $REGION."
  warn "Este script passa --region explicitamente, entao segue; mas os comandos"
  warn "soltos do plano assumem $REGION.  aws configure set region $REGION"
fi

BUDGETS="$(aws budgets describe-budgets --account-id "$ACCOUNT" --max-results 1 \
  --query 'Budgets[0].BudgetName' --output text 2>/dev/null || echo ERRO)"
if [ "$BUDGETS" = "None" ] || [ "$BUDGETS" = "ERRO" ] || [ -z "$BUDGETS" ]; then
  warn "Nenhum budget alarm encontrado nesta conta (ou sem permissao para ler)."
  warn "A conta nao tem credito e o free tier expirou: esse alarme e o unico"
  warn "aviso entre um erro e uma fatura de verdade. Task 0, passo 4."
else
  ok "budget alarm: $BUDGETS"
fi

# --------------------------------------------- Task 1, Passo 1: o bucket
step "Task 1, Passo 1 — bucket de estado $BUCKET"

if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1; then
  ok "ja existe"
else
  # O --create-bucket-configuration e obrigatorio fora de us-east-1: sem ele a
  # AWS responde IllegalLocationConstraintException.
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  ok "criado"
fi

# Os dois PUT abaixo sao idempotentes de proposito: rodar sempre corrige um
# bucket que alguem mexeu a mao.
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" --region "$REGION" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$BUCKET" --region "$REGION" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

VERSIONING="$(aws s3api get-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
  --query Status --output text 2>/dev/null || echo None)"
[ "$VERSIONING" = "Enabled" ] || die "Versionamento do bucket esta '$VERSIONING'.
    Nao e opcional: e o que permite voltar um estado corrompido."
ok "versionamento habilitado, acesso publico bloqueado"

# -------------------------------------------- Task 1, Passo 7: init de verdade
step "Task 1, Passo 7 — terraform init contra o S3"

cd "$TF_DIR"
# -reconfigure porque a sessao offline rodou `init -backend=false`; sem isso o
# Terraform pergunta sobre migracao de estado e trava num prompt.
terraform init -input=false -reconfigure
terraform validate
ok "backend inicializado e configuracao valida"

# ------------------------------------------------- Task 2, Passo 4: o apply
step "Task 2, Passo 4 — plan"

PLAN_FILE="$(mktemp -t prumo-plan.XXXXXX)"
trap 'rm -f "$PLAN_FILE"' EXIT

terraform plan -input=false -out="$PLAN_FILE"

echo
echo "    Sao 7 recursos: ecr.tf (4) + oidc.tf (3), porque a Task 4 ja esta"
echo "    escrita na mesma pasta."
echo "    Custo: ECR cobra por GB armazenado (centavos). Nada aqui e a"
echo "    instancia: essa e a Task 5, e ainda nao tem HCL."

if [ "$PLAN_ONLY" -eq 1 ]; then
  echo
  ok "--plan-only: parando antes do apply."
  exit 0
fi

if [ "$ASSUME_YES" -eq 0 ]; then
  echo
  read -r -p "    Aplicar? [y/N] " ANSWER
  case "$ANSWER" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "    Abortado. Nada foi aplicado."; exit 0 ;;
  esac
fi

terraform apply -input=false "$PLAN_FILE"

# ------------------------------------------------------------------ o que vem
step "Pronto. O que fazer agora"

echo
terraform output
cat <<'NEXT'

  1. Ponha o github_deploy_role_arn acima como o secret AWS_DEPLOY_ROLE_ARN nos
     tres repos (Prumo, Prumo-Angular, Prumo-DevOps). Task 4.

  2. Task 3 — gere os segredos e guarde no gerenciador de senhas ANTES de
     qualquer outra coisa:

         scripts/aws/gen-secrets.sh

  3. Task 5 — a instancia Lightsail. O HCL dela AINDA NAO EXISTE; e a proxima
     coisa a escrever, e e a primeira que custa dinheiro de verdade
     (~US$ 12/mes, fixos). Confirme antes o id do blueprint, que a AWS renomeia
     entre releases:

         aws lightsail get-blueprints --region sa-east-1 \
           --query "blueprints[?contains(blueprintId,'amazon_linux')].[blueprintId,name]" \
           --output table

NEXT
