#!/usr/bin/env bash
#
# Task 3, Passo 1 — gera os segredos do ambiente.
#
# Estes valores NAO ficam guardados em lugar nenhum na AWS. O que sai daqui vai
# para o seu gerenciador de senhas agora, e para o .env da maquina na Task 7.
# Perdeu, nao recupera: recria e reconfigura tudo.
#
# Uso:
#   scripts/aws/gen-secrets.sh                  # imprime na tela
#   scripts/aws/gen-secrets.sh -o ~/prumo.env   # escreve num arquivo (modo 600)
#
# Rodar de novo gera valores DIFERENTES. Nao rode "so para conferir" depois de
# a maquina existir: trocar JWT_KEY desloga todo mundo, trocar as senhas do
# Postgres quebra a API ate voce atualizar o .env de la.

set -euo pipefail

OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)  OUT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null || { echo "openssl nao esta no PATH." >&2; exit 1; }

# O tr -d '/+=' existe porque esses caracteres quebram a connection string do
# Postgres quando entram na senha sem escape. A chave do JWT nao passa por
# connection string nenhuma, entao ela fica com o base64 inteiro.
rand_pw() { openssl rand -base64 24 | tr -d '/+='; }

emit() {
  cat <<EOF
# Segredos do ambiente de dev na AWS — gerados em $(date -u '+%Y-%m-%d %H:%M UTC')
#
#   JWT_KEY                  assina os tokens; trocar desloga todo mundo
#   POSTGRES_PASSWORD        superusuario do Postgres, usado so na criacao do volume
#   PRUMO_APP_PASSWORD       role prumo_app, sem DDL — e com ela que a API serve
#   PRUMO_MIGRATOR_PASSWORD  role prumo_migrator, que roda a migration no startup
#   SEED_ADMIN_PASSWORD      primeiro login no sistema — ESCOLHA A MAO, ver abaixo

JWT_KEY=$(openssl rand -base64 48)
POSTGRES_PASSWORD=$(rand_pw)
PRUMO_APP_PASSWORD=$(rand_pw)
PRUMO_MIGRATOR_PASSWORD=$(rand_pw)

# SEED_ADMIN_PASSWORD nao e gerada aqui de proposito: ela precisa passar na
# politica do Identity (minimo 6, com digito, minuscula e maiuscula — ver
# DatabaseConfiguration.cs) e e a senha do primeiro login no piloto. Escolha uma
# de verdade, nao TrocarDepois1.
SEED_ADMIN_PASSWORD=
EOF
}

if [ -n "$OUT" ]; then
  [ -e "$OUT" ] && { echo "$OUT ja existe. Nao vou sobrescrever." >&2; exit 1; }
  ( umask 077; emit > "$OUT" )
  chmod 600 "$OUT" 2>/dev/null || true
  echo "Escrito em $OUT."
  echo
  echo "No Windows o modo 600 nao vale nada: o arquivo herda a ACL da pasta."
  echo "Escreva num lugar que so voce le, ou deixe na tela e nem crie arquivo."
  echo "AVISO: esse arquivo e texto puro. Copie para o gerenciador de senhas e"
  echo "apague-o. Nunca o commite — o .env mora na maquina, nao no repo."
else
  emit
  echo
  echo "AVISO: isso acabou de entrar no scrollback e no historico do terminal."
  echo "Copie para o gerenciador de senhas e feche a janela."
fi
