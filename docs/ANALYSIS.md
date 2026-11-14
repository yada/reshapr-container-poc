# reShapr ⇄ apple/container — evidence report

> Static analysis written before the tests; measured results are in [FINDINGS.md](FINDINGS.md) and supersede the "[static]" claims.

Method: static reading of `/orca/reshapr` (3dd7a4c), `/orca/container` (d6f107c7), `/orca/reshapr-sbx-poc`. The `container` CLI is not installed locally, so nothing below was run; claims are tagged **[static]**. Runtime checks are in the checklist at the end.

## 1. What each side is
- **reShapr**: control plane + MCP proxy (gateway) + Postgres, shipped as OCI images (Dockerfile.jvm/native under `control-plane/` and `proxy/`). Local stack is started by `reshapr run`.
- **apple/container**: macOS 26 / Apple silicon runtime, one lightweight VM per container, OCI-compatible, vmnet networking, embedded DNS (`docs/technical-overview.md`).
They sit at different layers: container = *where reShapr's processes run*; reShapr = *what an AI agent can do with APIs*. So the relation is runtime-host (integrate/benefit) and agent-sandbox neighbour (complement).

## 2. Findings with evidence

| # | Finding | Evidence | Impact |
|---|---|---|---|
| F1 | `reshapr run` only supports `docker`/`podman` and shells out to `<engine> compose up -d` on a downloaded compose file | `cli/src/commands/run.ts:38,72`; `cli/src/utils/containers.ts:35-76` | `container` can't be used today; there is no `container compose` |
| F2 | reShapr's stack uses compose features container lacks: `depends_on`, `healthcheck`, `restart: on-failure`, `extra_hosts: host-gateway` | `install/docker-compose.yml`; `skills/container/references/docker-migration.md` ("no `--restart`", "no equivalent" for compose) | Needs a script with readiness loop (`container exec ... pg_isready` / curl `/q/health/ready`) and supervisor (launchd) |
| F3 | Proxy→control-plane and control-plane→host IdP use `host.docker.internal` | `install/start-proxy.sh`, compose files | On container: `sudo container system dns create host.container.internal --localhost <ip>` (`docs/host-integration.md`); sudo + pf limitations; or use container names on default net (`<name>.test`) |
| F4 | **Gateway clustering via JGroups DNS_PING needs one DNS name returning several A records** (`reshapr.infinispan.dns-query=reshapr-gateways`) | `install/docker-compose-cluster.yml:4-6,88,118`; `proxy/src/main/resources/infinispan.xml:41-50` | See F5 |
| F5 | **container cannot provide that today**: an alias already owned by another host is rejected (`.exists`), and the DNS table maps a name to a single IPv4 (`hosts4: [String: IPv4Address]`, answer `[record]`) | `Sources/Services/Network/Server/AttachmentAllocator.swift:44-49,60-80`; `Sources/DNSServer/Handlers/HostTableResolver.swift:25-30,83-84` | Multi-gateway DNS_PING cluster fails on plain containers. Single-node (`reshapr-local` default stack in Dockerfile.jvm) is fine. Multi-node should run in K8s (F7) |
| F6 | Bare-name discovery on custom networks is missing; only domain-qualified names on `default` | `docs/networking.md:85-100` (apple/container#1809, apple/container#856) | Wire by `<name>.test` on default network |
| F7 | container ships local Kubernetes (`container cluster create`, `--shared-image-store`, multi-node, custom CNI); reShapr already has a K8s DNS_PING stack (`reshapr-k8s`) | `docs/cluster.md`; `infinispan.xml:18,41` | Natural place to test reShapr's multi-gateway/Helm path on a Mac |
| F8 | container gives per-container VM isolation, `--read-only`, `--cap-drop`, `--env-file`, `--publish`, `--publish-socket`, Keychain integration | `docs/command-reference.md:30-79`; `docs/technical-overview.md` | Hardening for the control plane that holds AES-GCM-encrypted secrets (`RESHAPR_ENCRYPTION_KEYS_*`) |
| F9 | reShapr already pairs with a sandbox: sbx kits isolate the agent, reShapr governs the API, key injected by sbx proxy | `reshapr-sbx-poc/README.md`, `docs/PLAN.md` §1 | Same pattern is possible on container but **container lacks sbx's egress allow-list and credential-injection proxy** (no such feature in `Sources/` or docs) — [static] |
| F10 | container has an agent skill (`skills/container/`) and a Docker→container mapping | `skills/container/SKILL.md` | Precedent/home for a reShapr-on-container recipe; reshapr-agent-skills repo exists |
| F11 | container exposes only XPC (no HTTP/OpenAPI surface) | `Sources/ContainerXPC`, `Sources/Services/*` | reShapr can't wrap container's API without a new shim — speculative |
| F12 | Images: reShapr publishes registry.reshapr.io / quay.io OCI images; container "consumes and produces standard OCI images" | `README.md` badges; `docs/technical-overview.md`; sbx-poc says multi-arch | Should run, including arm64; verify arm64 tag existence per release |

## 3. Opportunity matrix

| # | Direction | Type | Basis | Blockers | Effort | Verdict |
|---|---|---|---|---|---|---|
| 1 | `reshapr run --engine container`: generate a `container run` script (postgres → ctrl → proxy) instead of compose | Integrate | F1,F2,F3 | readiness loops, restart, host alias sudo | M | **Do first** for single-node dev |
| 2 | Docs: "Run reShapr on apple/container" (script, DNS domain setup, ports 5555/7777/3333) | Benefit | F2,F3,F6 | none | S | **Do first** (precedes #1) |
| 3 | Test reShapr multi-gateway + Helm on `container cluster` | Complement | F7 | verify chart/image pull on shared image store | S | Good, validates clustering |
| 4 | Agent-in-container-VM + reShapr as governed API (container counterpart to sbx-poc) | Complement | F8,F9 | no egress allow-list / credential-injection; key stays in env | M | Viable but weaker; position sbx as stronger |
| 5 | Harden control-plane in container (`--read-only`, `--cap-drop ALL`, VM isolation) | Benefit | F8 | verify Quarkus works read-only w/ tmp mounts | S | Cheap win |
| 6 | reShapr agent skill / recipe next to `skills/container` | Integrate (docs) | F10 | none | S | Low-risk |
| 7 | DNS_PING cluster on plain containers | — | F4,F5 | container DNS single-A + exclusive alias | needs upstream | **Blocked** |
| 8 | Expose container's operations as MCP via reShapr | Complement | F11 | no HTTP API | L | Speculative, skip |

## 4. Upstream asks
- **reShapr**: add `container` as engine (script generator or detection that refuses with guidance); make `host.docker.internal` configurable (env/compose var) so non-Docker engines can inject a host alias; document single-node-only on engines without multi-A DNS.
- **apple/container**: allow shared alias / multi-A answers (round-robin) for service discovery; bare-name resolution on custom networks (apple/container#1809); host alias without sudo; health checks/restart policy.

## 5. Runtime verification checklist (not run; needs a Mac with `container`)
1. Postgres + control-plane + proxy start via `container run`; `curl -f :5555/q/health/ready` ok.
2. Proxy reaches ctrl via `ctrl.test` and via `host.container.internal`.
3. Two containers with same alias: confirm `.exists` error (F5) and `dig` returns one A.
4. Control plane with `--read-only --cap-drop ALL` boots.
5. `container cluster create` + reShapr Helm/DNS_PING forms 2-node cluster.
6. arm64 images pull from registry.reshapr.io.

## 6. Bottom line
- **Benefit/integrate (works now in principle)**: single-node reShapr on container with a script — better VM isolation, no Docker Desktop needed.
- **Complement**: container = runtime + local K8s; reShapr = governance layer for agents. Pairing exists with sbx; container lacks the egress/credential proxy to replace it.
- **Not possible yet**: multi-gateway DNS_PING on plain containers (F5) — use `container cluster`.
