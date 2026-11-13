# reshapr-container-poc

Proof of concept: run the **[reShapr](https://github.com/reshaprio/reshapr) MCP runtime stack on [apple/container](https://github.com/apple/container)** (Linux containers as lightweight VMs on macOS), without Docker or Compose.

`reshapr run --engine apple` (merged in [reshaprio/reshapr#620](https://github.com/reshaprio/reshapr/pull/620), in releases after 1.1.1) now starts the stack on apple/container from the release compose files. apple/container itself has no compose, restart policy, healthcheck or `host-gateway`, so this repo keeps a script equivalent (what the CLI does not cover: hardened mode, configurable ports, `verify.sh`, `container cluster`) and records what works and what does not. Results: [docs/FINDINGS.md](docs/FINDINGS.md).

| Script | What it does |
|---|---|
| `scripts/up.sh` | postgres, control plane and gateway with `container run`, gated by readiness loops; `--ui` adds the web UI |
| `scripts/verify.sh` | imports Open-Meteo and runs MCP `initialize`, `tools/list`, `tools/call` through the gateway, result printed with `jq` |
| `scripts/down.sh` | removes the three containers |
| `scripts/k8s-cluster.yaml` | 2-gateway clustered stack for `container cluster create` (DNS_PING, encrypted JGroups) |

## Status

Validated on macOS 27.2 (arm64), `container` 1.7.1, reShapr 1.1.0 (details in [docs/FINDINGS.md](docs/FINDINGS.md)):

| Done | |
|---|---|
| T1-T5 | native arm64 images, stack ready in ~18 s, MCP end to end (`make verify`), hardened run (`--read-only --cap-drop ALL`) |
| T6-T7 | duplicate alias rejected; 2 gateways share MCP sessions inside a `container cluster` |
| T3, T9 | sudo DNS: `<name>.test` and `host.container.internal` pass; `reshapr run --engine apple` merged ([PR #620](https://github.com/reshaprio/reshapr/pull/620)) and verified on `main` |
| Extras | opt-in web UI (`make up-ui`), `make` usage page |

## Next steps

1. Done: `reshapr run --engine apple` (T9), merged in [PR #620](https://github.com/reshaprio/reshapr/pull/620) and verified on `main`. Re-test on the first release that includes it (1.1.1 does not).
2. Done: the sudo DNS checks (`<name>.test` and `host.container.internal` both pass) and the `docker-compose-cluster.yml` failure on Docker (F8), fixed upstream in [#621](https://github.com/reshaprio/reshapr/issues/621) (keystore-init container, not re-tested here). Check whether `scripts/k8s-cluster.yaml` still needs its keystore Secret.
3. T8: an agent inside a container VM reaching tools only through reShapr.
4. Upstream issues. Filed: reShapr [#619](https://github.com/reshaprio/reshapr/issues/619) (`--engine apple`, done), [#621](https://github.com/reshaprio/reshapr/issues/621) (cluster keystore, done). To file: reShapr discovery retry; apple/container shared aliases / multi-A DNS answers, sudo resolver dependency, `rs.test` kubeconfig.
5. Docs on reshapr.io and a recipe in `reshapr-agent-skills`.

## Prerequisites

Apple silicon, macOS 26+, `container` 1.7+ (`container system start`), the reShapr CLI (`npm i -g @reshapr/reshapr-cli`), `curl`. No sudo is needed for anything here. Optional, with sudo: `container system dns create test` adds `<name>.test` resolution, and `dns create host.container.internal --localhost <ip>` lets containers reach host services (its rule is lost on reboot).

## Quick start

```bash
make up        # ports 5555 / 7777 on 127.0.0.1 (override: RESHAPR_CTRL_HOST_PORT, RESHAPR_GATEWAY_HOST_PORT)
make verify    # uses an isolated HOME (.state/home), your reshapr CLI session is untouched
make down
```

Web UI (opt-in, like `reshapr run --ui`): `make up-ui` or `./scripts/up.sh --ui` serves http://127.0.0.1:3333 (override: `RESHAPR_UI_HOST_PORT`, `RESHAPR_UI_IMAGE`; login admin / password).

Hardened control plane: `RESHAPR_EXTRA_RUN_ARGS="--read-only --cap-drop ALL --tmpfs /tmp" make up`.

Containers are wired by IP (`container ls`) so no sudo is needed. `<name>.test` names also work, but only after `sudo container system dns create test`, because in-container lookups go through the macOS resolver.

## Clustered gateways (container cluster)

```bash
container cluster create --name rs --shared-image-store
container cluster list --nodes                     # node IP
# the kubeconfig uses rs.test (needs sudo DNS); use the node IP instead:
K="kubectl --server https://<node-ip>:6443 --insecure-skip-tls-verify"
# keystore for JGroups SYM_ENCRYPT, generated with the JDK of the proxy image:
mkdir -p .state/ks && container run --rm -v $PWD/.state/ks:/out --entrypoint keytool \
  registry.reshapr.io/reshapr/reshapr-proxy:1.1.0 -genseckey -alias reshapr-cluster -keyalg AES \
  -keysize 256 -storetype JCEKS -keystore /out/reshapr-cluster.jceks -storepass changeit -keypass changeit
$K apply -f scripts/k8s-cluster.yaml   # creates the namespace (the Secret below needs it, so apply twice)
$K -n reshapr create secret generic reshapr-cluster-keystore --from-file=.state/ks/reshapr-cluster.jceks
$K apply -f scripts/k8s-cluster.yaml
$K -n reshapr rollout restart deploy/gateway   # gateways do not retry discovery if the control plane was not ready yet
```

`changeit` and the demo tokens/keys are throwaway values, do not reuse them.

## License

Apache-2.0
