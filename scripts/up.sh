#!/bin/bash
# Start the reShapr single-node stack (postgres, control plane, gateway) on apple/container.
# Equivalent of install/docker-compose-all-in-one.yml, without compose.
# Usage: up.sh [--ui]   (or RESHAPR_UI=1) also starts the web UI on 127.0.0.1:${RESHAPR_UI_HOST_PORT:-3333}
set -euo pipefail

UI="${RESHAPR_UI:-0}"
for arg in "$@"; do
  case "$arg" in
    --ui) UI=1 ;;
    *) echo "usage: $0 [--ui]" >&2; exit 2 ;;
  esac
done

RELEASE="${RESHAPR_RELEASE:-1.1.1}"
REG="${RESHAPR_REGISTRY:-registry.reshapr.io/reshapr}"
EXTRA="${RESHAPR_EXTRA_RUN_ARGS:-}"
CTRL_TOKEN="my-super-secret-token-xyz"

wait_for() { # <description> <timeout-s> <command...>
  local d=$1 t=$2; shift 2
  for _ in $(seq "$t"); do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
  echo "timeout waiting for $d" >&2; return 1
}

container system status >/dev/null

# Host-side name resolution of <name>.<domain> needs `sudo container system dns create <domain>`,
# and containers resolve peers through the host resolver. Without it we wire containers by IP.
ip_of() { container ls | awk -v n="$1" '$1==n {sub("/.*","",$6); print $6}'; }
CTRL_PORT="${RESHAPR_CTRL_HOST_PORT:-5555}"
GW_PORT="${RESHAPR_GATEWAY_HOST_PORT:-7777}"

container run -d --name reshapr-postgres \
  -e POSTGRES_USER=reshapr -e POSTGRES_PASSWORD=reshapr -e POSTGRES_DB=reshapr \
  postgres:17-alpine
wait_for postgres 60 container exec reshapr-postgres pg_isready -U reshapr -q

# shellcheck disable=SC2086
container run -d --name reshapr-control-plane -p 127.0.0.1:${CTRL_PORT}:5555 $EXTRA \
  -e QUARKUS_DATASOURCE_JDBC_URL="jdbc:postgresql://$(ip_of reshapr-postgres):5432/reshapr" \
  -e QUARKUS_DATASOURCE_USERNAME=reshapr -e QUARKUS_DATASOURCE_PASSWORD=reshapr \
  -e RESHAPR_ADMIN_NAME=admin -e RESHAPR_ADMIN_PASSWORD=password \
  -e RESHAPR_ADMIN_EMAIL=reshapr@example.com \
  -e RESHAPR_DEFAULT_GATEWAY_TOKENS="$CTRL_TOKEN" \
  -e RESHAPR_ENCRYPTION_KEYS_V1=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8= \
  -e RESHAPR_ENCRYPTION_ACTIVE_KEY_ID=v1 \
  -e RESHAPR_ENCRYPTION_KEY=my-super-secret-key-32-char-long \
  "$REG/reshapr-ctrl:$RELEASE"
wait_for control-plane 180 curl -fs http://127.0.0.1:${CTRL_PORT}/q/health/ready

container run -d --name reshapr-gateway-01 -p 127.0.0.1:${GW_PORT}:7777 \
  -e RESHAPR_CTRL_HOST="$(ip_of reshapr-control-plane)" -e RESHAPR_CTRL_PORT=5555 \
  -e RESHAPR_CTRL_TOKEN="reshapr-$CTRL_TOKEN" \
  "$REG/reshapr-proxy:$RELEASE"

if [ "$UI" = 1 ]; then
  UI_PORT="${RESHAPR_UI_HOST_PORT:-3333}"
  # Same dev admin key as install/docker-compose-ui-addon.yml, fetched from upstream unless provided.
  API_KEY="${RESHAPR_ADMIN_API_KEY:-$(curl -fsSL "https://raw.githubusercontent.com/reshaprio/reshapr/main/install/docker-compose-ui-addon.yml" | sed -n 's/.*RESHAPR_ADMIN_API_KEY=//p')}"
  container run -d --name reshapr-web-ui -p 127.0.0.1:${UI_PORT}:3333 \
    -e RESHAPR_CTRL_URL="http://$(ip_of reshapr-control-plane):5555" \
    -e RESHAPR_ADMIN_API_KEY="$API_KEY" \
    -e RESHAPR_WEBUI_PUBLIC_URL="http://localhost:${CTRL_PORT}" \
    -e ORIGIN="http://localhost:${UI_PORT}" -e BODY_SIZE_LIMIT=12M \
    "${RESHAPR_UI_IMAGE:-$REG/reshapr-ui:nightly}"
  wait_for web-ui 60 curl -fs -o /dev/null http://127.0.0.1:${UI_PORT}/
  echo "web ui: http://127.0.0.1:${UI_PORT}  (login admin / password)"
fi

echo "control plane: http://127.0.0.1:${CTRL_PORT}  gateway: http://127.0.0.1:${GW_PORT}"
