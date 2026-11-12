#!/bin/bash
set -uo pipefail
for c in reshapr-web-ui reshapr-gateway-01 reshapr-control-plane reshapr-postgres; do
  container stop "$c" >/dev/null 2>&1
  container delete "$c" >/dev/null 2>&1
done
