#!/bin/bash
# T4: import an OpenAPI as an MCP server and exercise it end to end through the gateway.
# Uses an isolated HOME so the reshapr CLI session of the host is untouched.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CTRL_PORT="${RESHAPR_CTRL_HOST_PORT:-5555}"
GW_PORT="${RESHAPR_GATEWAY_HOST_PORT:-7777}"
EXPOSITION="${EXPOSITION:-reshapr/open-meteo-weather-forecast-api-1-0-default}"
export HOME="${VERIFY_HOME:-$HERE/../.state/home}"
mkdir -p "$HOME"

reshapr login -s "http://localhost:${CTRL_PORT}" -u admin -p password >/dev/null
out="$(reshapr import \
  -u https://raw.githubusercontent.com/open-meteo/open-meteo/refs/heads/main/openapi/forecast.yml \
  --backendEndpoint https://api.open-meteo.com 2>&1)" || { echo "$out"; exit 1; }
echo "$out" | grep -E "Endpoints|Exposition Name" || true

"$HERE/mcp-smoke.sh" "http://127.0.0.1:${GW_PORT}/mcp/${EXPOSITION}"
