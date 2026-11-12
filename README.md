# reshapr-container-poc

Proof of concept: run the **[reShapr](https://github.com/reshaprio/reshapr) MCP runtime stack on [apple/container](https://github.com/apple/container)** (Linux containers as lightweight VMs on macOS), without Docker or Compose.

`reshapr run` only knows `docker` / `podman` + `compose`. apple/container has no compose, restart policy, healthcheck or `host-gateway`, so this repo provides a script equivalent and records what works and what does not. Results: [docs/FINDINGS.md](docs/FINDINGS.md).

| Script | What it does |
|---|---|
| `scripts/up.sh` | postgres, control plane and gateway with `container run`, gated by readiness loops |
| `scripts/verify.sh` | imports Open-Meteo and runs MCP `initialize`, `tools/list`, `tools/call` through the gateway |
| `scripts/down.sh` | removes the three containers |
| `scripts/k8s-cluster.yaml` | 2-gateway clustered stack for `container cluster create` (DNS_PING, encrypted JGroups) |

## Prerequisites

Apple silicon, macOS 26+, `container` 1.7+ (`container system start`), the reShapr CLI (`npm i -g @reshapr/reshapr-cli`), `curl`. No sudo is needed for anything here; the optional `sudo container system dns create` only adds `<name>.test` host resolution.

## Quick start

```bash
make up        # ports 5555 / 7777 on 127.0.0.1 (override: RESHAPR_CTRL_HOST_PORT, RESHAPR_GATEWAY_HOST_PORT)
make verify    # uses an isolated HOME (.state/home), your reshapr CLI session is untouched
make down
```

Web UI (opt-in, like `reshapr run --ui`): `make up-ui` or `./scripts/up.sh --ui` serves http://127.0.0.1:3333 (override: `RESHAPR_UI_HOST_PORT`, `RESHAPR_UI_IMAGE`; login admin / password).

Hardened control plane: `RESHAPR_EXTRA_RUN_ARGS="--read-only --cap-drop ALL --tmpfs /tmp" make up`.

Containers are wired by IP (`container ls`), because `<name>.<domain>` resolution inside containers goes through the macOS resolver and needs the sudo step.

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
