#!/usr/bin/env bash
# Brings the stack up on the host. Runs from YOUR machine, not from CI: Lightsail is not
# reachable by SSM Run Command, and the alternative would be opening port 22 to the world
# and storing a private key in a GitHub secret.
#
# Usage: ./deploy.sh          (uses the :latest images)
#        ./deploy.sh <sha>    (pins a specific version of both images)
#
# Requires: the instance exists, /opt/prumo/.env is written on it (see
# docs/RUNBOOK.md) and ~/.ssh/prumo-dev is the private key of the host's key pair.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOST="$(cd "$HERE/../terraform/aws/dev" && terraform output -raw public_ip)"
SSH="ssh -i $HOME/.ssh/prumo-dev ec2-user@$HOST"
TAG="${1:-latest}"

echo "==> deploying $TAG to $HOST"

# The deploy files travel over SSH; the host needs no git credential.
tar czf - -C "$HERE" docker-compose.yml Caddyfile db | $SSH "tar xzf - -C /opt/prumo"

# The heredoc is UNQUOTED on purpose: $TAG has to be expanded by YOUR machine, which is
# why \$AWS_REGION and \$ECR_REGISTRY are escaped, to be left for the remote host.
# Changing that breaks silently.
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

echo "==> done."
