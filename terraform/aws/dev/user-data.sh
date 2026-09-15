#!/bin/bash
set -euxo pipefail

# Instalacao de maquina pura: sem templatefile, sem variavel interpolada, sem
# segredo. Por isso este script e o mesmo em qualquer ambiente e nao precisa ser
# reaplicado quando um valor muda.
#
# AVISO, diferente da EC2: o Lightsail nao tem o equivalente de
# user_data_replace_on_change. Mudar este arquivo NAO recria a instancia — o
# Terraform aceita a mudanca e nao faz nada com ela. Para valer, e preciso
# `terraform taint aws_lightsail_instance.app` ou aplicar a mudanca a mao por
# SSH. Quando importar, vai importar em silencio.

# --- Docker ---
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user

# O AL2023 nao empacota o plugin compose v2; ele vem do release do Docker.
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# --- AWS CLI, para o login no ECR ---
dnf install -y awscli-2 || dnf install -y aws-cli

# --- diretorio de deploy ---
# Os arquivos (docker-compose.yml, Caddyfile, db/roles.sql) chegam pelo deploy da
# Task 10. No primeiro boot eles ainda nao estao, e isso nao e erro.
mkdir -p /opt/prumo/db
chown -R ec2-user:ec2-user /opt/prumo
