#!/bin/bash
set -euxo pipefail

# Plain machine setup: no templatefile, no interpolated variable, no secret. That is why
# this script is the same in any environment and does not need re-applying when a value
# changes.
#
# WARNING, unlike EC2: Lightsail has no equivalent of user_data_replace_on_change.
# Changing this file does NOT re-create the instance — Terraform accepts the change and
# does nothing with it. To make it count, `terraform taint aws_lightsail_instance.app` or
# apply the change by hand over SSH.

# --- Docker ---
dnf install -y docker git
systemctl enable --now docker
usermod -aG docker ec2-user

# AL2023 does not package the compose v2 plugin; it comes from Docker's release.
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# --- AWS CLI, for the ECR login ---
dnf install -y awscli-2 || dnf install -y aws-cli

# --- deploy directory ---
# The files (docker-compose.yml, Caddyfile, db/roles.sql) arrive with deploy/deploy.sh.
# On first boot they are not there yet, and that is not an error.
mkdir -p /opt/prumo/db
chown -R ec2-user:ec2-user /opt/prumo
