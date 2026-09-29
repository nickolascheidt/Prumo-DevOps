#!/usr/bin/env bash
#
# Generates the environment's secrets, in the format of deploy/.env.example.
#
# These values are NOT stored anywhere in AWS. What comes out of here goes to your
# password manager now, and to /opt/prumo/.env on the host. Lost means lost: regenerate
# and reconfigure everything.
#
# Usage:
#   scripts/aws/gen-secrets.sh                  # prints to the screen
#   scripts/aws/gen-secrets.sh -o ~/prumo.env   # writes a file (mode 600)
#
# Running it again generates DIFFERENT values. Do not run it "just to check" once the
# host exists: a new JWT_KEY signs everyone out, new Postgres passwords break the API
# until the host's .env is updated.

set -euo pipefail

OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)  OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null || { echo "openssl is not on the PATH." >&2; exit 1; }

# tr -d '/+=' because those characters break the Postgres connection string when they
# go into a password unescaped. The JWT key goes through no connection string, so it
# keeps the whole base64 alphabet.
rand_pw() { openssl rand -base64 24 | tr -d '/+='; }

emit() {
  cat <<EOF
# Prumo dev environment secrets — generated $(date -u '+%Y-%m-%d %H:%M UTC')
#
#   JWT_KEY                  signs the tokens; changing it signs everyone out
#   POSTGRES_PASSWORD        Postgres superuser, only used when the volume is created
#   PRUMO_APP_PASSWORD       prumo_app role, no DDL — the API serves with it
#   PRUMO_MIGRATOR_PASSWORD  prumo_migrator role, runs the migrations at startup
#   SEED_ADMIN_PASSWORD      the first sign-in — CHOOSE IT BY HAND, see below

JWT_KEY=$(openssl rand -base64 48)
POSTGRES_PASSWORD=$(rand_pw)
PRUMO_APP_PASSWORD=$(rand_pw)
PRUMO_MIGRATOR_PASSWORD=$(rand_pw)

# SEED_ADMIN_PASSWORD is not generated on purpose: it has to pass the API's Identity
# password policy (at least 6 characters, with a digit, a lower-case and an upper-case
# letter) and it is the first sign-in. Pick a real one.
SEED_ADMIN_PASSWORD=
EOF
}

if [ -n "$OUT" ]; then
  [ -e "$OUT" ] && { echo "$OUT already exists. Not overwriting it." >&2; exit 1; }
  ( umask 077; emit > "$OUT" )
  chmod 600 "$OUT" 2>/dev/null || true
  echo "Written to $OUT."
  echo
  echo "On Windows mode 600 means nothing: the file inherits the folder's ACL."
  echo "Write it somewhere only you can read, or keep it on screen and skip the file."
  echo "WARNING: that file is plain text. Copy it to your password manager and delete"
  echo "it. Never commit it — the .env lives on the host, not in the repo."
else
  emit
  echo
  echo "WARNING: this just went into your scrollback and terminal history."
  echo "Copy it to your password manager and close the window."
fi
