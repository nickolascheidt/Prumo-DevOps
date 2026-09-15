#!/usr/bin/env bash
# Sobe a stack na máquina do piloto. Roda da SUA máquina, não do CI: o Lightsail
# não é alcançável por SSM Run Command, e a alternativa seria abrir a porta 22
# para o mundo e guardar uma chave privada num secret do GitHub.
#
# Uso: ./deploy.sh          (usa as imagens :latest)
#      ./deploy.sh <sha>    (fixa uma versão específica das duas imagens)
#
# Pré-requisitos: a instância existe (Task 5), o .env está escrito nela (Task 7)
# e ~/.ssh/prumo-dev é a chave privada gerada na Task 5, Passo 1.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOST="$(cd "$HERE/../terraform/aws/dev" && terraform output -raw public_ip)"
SSH="ssh -i $HOME/.ssh/prumo-dev ec2-user@$HOST"
TAG="${1:-latest}"

echo "==> deploy de $TAG para $HOST"

# Os arquivos de deploy viajam por SSH; a máquina não precisa de credencial de git.
tar czf - -C "$HERE" docker-compose.yml Caddyfile db | $SSH "tar xzf - -C /opt/prumo"

# O <<EOF SEM aspas é proposital aqui, ao contrário do .env da Task 7: $TAG
# precisa ser expandido pela SUA máquina, e por isso \$AWS_REGION e
# \$ECR_REGISTRY estão escapados para sobrarem para a máquina remota. Trocar isso
# quebra de um jeito silencioso.
$SSH bash -s <<EOF
set -euo pipefail
cd /opt/prumo
sed -i "s/^API_TAG=.*/API_TAG=$TAG/" .env
sed -i "s/^WEB_TAG=.*/WEB_TAG=$TAG/" .env
set -a && . ./.env && set +a
aws ecr get-login-password --region "\$AWS_REGION" \
  | docker login --username AWS --password-stdin "\$ECR_REGISTRY"
docker compose pull
docker compose up -d
docker image prune -f
docker compose ps
EOF

echo "==> pronto."
