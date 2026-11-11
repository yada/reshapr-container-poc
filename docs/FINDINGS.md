# Findings: reShapr on apple/container

Tested 2026-11-11 on macOS 27.2 (build 26B123), Apple silicon, `container` 1.7.1 (extracted from the release `.pkg` into a user directory, no sudo), reShapr 1.1.0 images from `registry.reshapr.io`.

## Results

| # | Test | Result |
|---|---|---|
| T1 | Pull postgres:17-alpine, reshapr-ctrl:1.1.0, reshapr-proxy:1.1.0 | **Pass**, native `linux/arm64` |
| T2 | Single-node stack with `container run` (about 18 s from `up.sh` to ready) | **Pass**, control plane `/q/health/ready` UP, gateway registers (`reshapr-gateway-00`) |
| T3 | Proxy to control plane | **Pass by IP**. By name (`<name>.test`) **fails without sudo**, see F2. `host.container.internal` not tested (needs sudo) |
| T4 | Import Open-Meteo, MCP `initialize`, `tools/list`, `tools/call` via gateway | **Pass** (`isError:false`, real forecast) |
| T5 | Control plane `--read-only --cap-drop ALL` | **Pass with `--tmpfs /tmp`** (Vert.x cache dir needs a writable `/tmp`); MCP verify passes on the hardened stack |
| T6 | Two containers sharing alias `svc.test` | **Rejected**: `Error: alias(es) already exist: ["svc.test"]` |
| T7 | `container cluster create --shared-image-store`, 2 gateways with `reshapr-k8s` stack | **Pass** after fixes below. MCP session created on gateway 1 is accepted by gateway 2 (`tools/list`), so state is replicated |
| T8 | Agent in a container VM through reShapr | **Not run** (no egress allow-list or credential-injection to compare in practice) |
| T9 | `reshapr run --engine container` | **Not implemented**; `scripts/up.sh` is the manual equivalent |

## Findings

- **F1 No compose-equivalents.** Script uses `container exec ... pg_isready` and a curl loop instead of `depends_on`/`healthcheck`. No `--restart`: a crashed container stays stopped.
- **F2 Name resolution needs sudo even container to container.** Containers register as `<name>.test` (seen in `container system logs`), but a container's resolver (192.168.65.1) forwards to macOS, which only knows `test` after `sudo container system dns create test`. Without it: `NXDOMAIN`/`UnknownHostException`. Docs describe it as two steps, but that the in-container lookup depends on step 2 is easy to miss.
- **F3 Shared alias rejected, DNS answers one A record.** Plain containers cannot form a DNS_PING cluster (needs several A records for one name). Use `container cluster` (T7, where the Kubernetes headless Service provides them).
- **F4 `container cluster` kubeconfig uses `rs.test`**, same sudo dependency. Workaround: `--server https://<node-ip>:6443 --insecure-skip-tls-verify`. `cluster create` also rewrites `~/.kube/config` and sets current-context (`cluster delete` removes its entries but not the current-context).
- **F5 `--shared-image-store` works**: pods ran locally pulled reShapr images without a registry.
- **F6 Host-to-container by IP works** (192.168.65.x via bridge101); first connection once failed with "no route to host" and succeeded on retry.
- **F7 Docker Desktop port clash.** A running Docker reShapr stack on 5555/7777 made the readiness probe false-positive. `up.sh` ports are configurable for that reason.
- **F8 (reShapr, independent of container)** `reshapr-k8s` stack requires a JCEKS keystore (`reshapr-cluster.jceks`, `reshapr.infinispan.encrypt.*`); without it the gateway returns HTTP 500 on first MCP request (`ISPN000541 ... FileNotFoundException: reshapr-cluster.jceks`). `install/docker-compose-cluster.yml` at reshapr 3dd7a4c sets no keystore, so it likely hits the same error (not run here).
- **F9 (reShapr)** Gateways that start before the control plane is ready log `Failed to fetch expositions during startup` and do not retry discovery until restarted (rollout restart fixed it). Compose `depends_on: service_healthy` hides this; Kubernetes needs an init wait or retry.
- **F10 `postgres:17-alpine` pull** unpacked several platforms (`linux/s390x` seen in output), about 2 min first time; reShapr images about 1 min each.

## Upstream candidates

- reShapr: `--engine container` (or documented script), configurable host alias instead of `host.docker.internal`, compose-cluster keystore (F8), discovery retry (F9).
- apple/container: multi-A / shared alias (F3), host-side DNS not required for container-to-container lookup (F2), kubeconfig by IP (F4), healthcheck/restart.

## Not verified

`host.container.internal`, the `sudo` DNS flow, `docker-compose-cluster.yml` failure (F8), agent-in-container sandbox (T8), macOS 15 behaviour.
