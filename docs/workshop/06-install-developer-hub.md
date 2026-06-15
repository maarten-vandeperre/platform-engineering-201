# 6. Install Developer Hub

Deploy a Developer Hub (`Backstage`) instance with dynamic plugins for Kubernetes, Topology, Tech Radar, and Keycloak SSO.

**Developer Hub vs Backstage:** RHDH is Red Hat’s distribution of Backstage. Everything you configure here — `app-config`, dynamic plugins, catalog locations, OIDC — is standard Backstage. Community Backstage on Kubernetes can run the same workshop with equivalent Helm/manifest setup; this repo’s install scripts target OpenShift.

Bootstrap runs this automatically. Manual install:

```bash
./scripts/install-developer-hub.sh    # operator path
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

Helm alternative:

```bash
./scripts/install-developer-hub-helm.sh
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

If Argo CD is ready, configure its token before or after RHDH config:

```bash
./scripts/setup-argocd-token.sh
./scripts/setup-developer-hub-config.sh
```

## Manifests (`manifests/gitops/developer-hub/`)

| File | Description |
|------|-------------|
| `app-config-rhdh.yaml` | OIDC, catalog locations, Argo CD, Kubernetes, Tech Radar |
| `dynamic-plugins-rhdh.yaml` | Kubernetes, Topology, Tech Radar, GitHub scaffolder plugins |
| `dynamic-plugins-pvc.yaml` | Persistent volume claim for the dynamic plugins cache |
| `dynamic-plugins-cache-deployment-patch.yaml` | Replaces ephemeral `dynamic-plugins-root` with the PVC |
| `dynamic-plugins-mcp.yaml` | MCP server and catalog/TechDocs tool plugins (Lightspeed) |
| `dynamic-plugins-aap.yaml` | Ansible Automation Platform frontend + scaffolder plugins |
| `app-config-aap-snippet.yaml` | AAP Controller connection, creator service, template catalog |
| `app-secrets-rhdh.yaml` | Secret template for tokens and OIDC client secret |
| `catalog-configmap.yaml` | Inline catalog entities (component, API, template) |
| `catalog-server.yaml` | HTTP server for catalog entities, OpenAPI file, Tech Radar JSON |
| `backstage-cr.yaml` | `Backstage` CR — creates route, mounts config + secrets |

Helm alternative: `manifests/helm/rhdh-values.yaml`

## Dynamic plugins cache (faster restarts)

By default, RHDH mounts `dynamic-plugins-root` as an **ephemeral** volume (`volumeClaimTemplate`). Every pod restart re-runs `install-dynamic-plugins` and re-downloads OCI plugin images (several minutes).

Enable the **persistent plugins cache** once per namespace:

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
```

This script:

1. Creates PVC `dynamic-plugins-root` (5Gi, `ReadWriteOnce`) from [`dynamic-plugins-pvc.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-pvc.yaml)
2. Patches the `redhat-developer-hub` Deployment to mount that PVC instead of an ephemeral claim
3. Rolls out Developer Hub once

On later restarts, when plugin packages and config checksums are unchanged, `install-dynamic-plugins` skips downloads and startup is much faster.

`setup-developer-hub-config.sh` calls the cache script automatically (without an extra rollout). Config changes still trigger a single pod restart.

### Script options

| Option | Purpose |
|--------|---------|
| *(none)* | Create PVC, patch deployment, roll out once |
| `--no-rollout` | Apply PVC/patch only; used by `setup-developer-hub-config.sh` to avoid a double restart |
| `--force-rollout` | Restart Developer Hub even when the PVC is already mounted |
| `--clear-lock` | Remove a stale `install-dynamic-plugins` lock file on the PVC when the init container hangs on `Waiting for lock release` (common after a crashed or killed pod) |

Clear a stale lock without changing the PVC:

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock
```

If the pod is still stuck, delete the Developer Hub pod so it recreates, or run `--clear-lock` again after the new pod is running.

### Troubleshooting the plugins cache

| Symptom | Fix |
|---------|-----|
| Init container stuck on `Waiting for lock release` | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` |
| Force re-download all plugins after config change | Delete PVC `dynamic-plugins-root` (cache rebuilds on next start) |
| Helm install | Run `./scripts/setup-developer-hub-dynamic-plugins-cache.sh` after `helm upgrade` (do not add `extraVolumes` in values — breaks chart volumes) |

See [Red Hat docs: Use the dynamic plugins cache](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/configuring_red_hat_developer_hub/use-the-dynamic-plugins-cache_configuring-rhdh).

## Developer Lightspeed

[Developer Lightspeed](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/interacting_with_red_hat_developer_lightspeed_for_red_hat_developer_hub/) adds an AI chat assistant (floating action button and `/lightspeed` page) to Developer Hub. The workshop connects it to **OpenAI** using the native OpenAI provider (not vLLM against `api.openai.com`).

### Configure in `workshop.env`

```bash
export LIGHTSPEED_ENABLED=true
export OPENAI_API_KEY=sk-your-openai-api-key
export OPENAI_MODEL=gpt-4o-mini          # optional; default gpt-4o-mini
export LIGHTSPEED_VLLM_MAX_TOKENS=4096   # optional max tokens hint
```

| Variable | Default | Description |
|----------|---------|-------------|
| `LIGHTSPEED_ENABLED` | `false` | Enable Lightspeed plugins, sidecars, and secrets |
| `OPENAI_API_KEY` | `changeme` | OpenAI platform API key ([platform.openai.com](https://platform.openai.com/)) |
| `OPENAI_MODEL` | `gpt-4o-mini` | Model id passed to the OpenAI provider |
| `LIGHTSPEED_VLLM_MAX_TOKENS` | `4096` | Token limit hint for inference providers |
| `LIGHTSPEED_SAFETY_GUARD` | `false` | Set `true` only if you run a Llama Guard safety server (`SAFETY_URL`); default disables moderation for OpenAI-only workshop |

### Install

`setup-developer-hub-config.sh` enables Lightspeed automatically when `LIGHTSPEED_ENABLED=true` and a valid `OPENAI_API_KEY` is set. Or run standalone:

```bash
./scripts/setup-developer-hub-lightspeed.sh
```

This script:

1. Creates ConfigMaps `lightspeed-stack`, `lightspeed-app-config`, and `lightspeed-rbac-policies`
2. Creates Secret `llama-stack-secrets` with `ENABLE_OPENAI=true` and your API key
3. Adds **Llama Stack** and **Lightspeed Core Service** sidecars to the Developer Hub pod
4. Initializes RAG content for product documentation (`init-rag-data` init container)
5. Registers Lightspeed dynamic plugins (frontend + backend) and **MCP** plugins (catalog + TechDocs tools)
6. Links Lightspeed to the RHDH MCP server (`mcp::backstage`) so chat can query the Software Catalog
7. Grants chat permissions to the workshop user (`RHDH_KEYCLOAK_USER`, default `devhub`)

| Manifest | Purpose |
|----------|---------|
| [`lightspeed-stack-configmap.yaml`](../../manifests/gitops/developer-hub/lightspeed-stack-configmap.yaml) | Lightspeed Core Service configuration (includes `mcp_servers` → local RHDH MCP endpoint) |
| [`lightspeed-app-config.yaml`](../../manifests/gitops/developer-hub/lightspeed-app-config.yaml) | CSP, prompts, RBAC policy path |
| [`lightspeed-llama-stack-secret.yaml`](../../manifests/gitops/developer-hub/lightspeed-llama-stack-secret.yaml) | LLM provider credentials (OpenAI) |
| [`dynamic-plugins-lightspeed.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-lightspeed.yaml) | Lightspeed frontend/backend plugins |
| [`dynamic-plugins-mcp.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-mcp.yaml) | MCP server and catalog/TechDocs tool plugins |
| [`lightspeed-mcp-token-secret.yaml`](../../manifests/gitops/developer-hub/lightspeed-mcp-token-secret.yaml) | Bearer token file for Lightspeed Core → MCP server auth |

After rollout, sign in and use **Lightspeed** from the sidebar (between Orchestrator and Notifications) or the floating spark button (bottom-right). Direct URL: `/lightspeed`.

### Model Context Protocol (MCP) — catalog-aware chat

When `LIGHTSPEED_ENABLED=true`, the workshop also enables **MCP** so Developer Lightspeed can query **your** Developer Hub catalog and TechDocs through tools (not just generic OpenAI answers).

> **Developer Preview:** MCP in RHDH 1.9 is a Developer Preview feature. See [Red Hat MCP documentation](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/interacting_with_model_context_protocol_tools_for_red_hat_developer_hub/index).

**Architecture**

```text
Lightspeed chat  →  Lightspeed Core  →  Llama Stack (MCP client)
                                              ↓
                         Developer Hub backend  /api/mcp-actions/v1
                                              ↓
                         software-catalog-mcp-tool  |  techdocs-mcp-tool
```

| Component | Purpose |
|-----------|---------|
| [`dynamic-plugins-mcp.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-mcp.yaml) | MCP server + catalog/TechDocs tool plugins |
| [`app-config-mcp.yaml`](../../manifests/gitops/developer-hub/app-config-mcp.yaml) | Static `MCP_TOKEN` and `pluginSources` |
| [`lightspeed-stack-configmap.yaml`](../../manifests/gitops/developer-hub/lightspeed-stack-configmap.yaml) | `mcp_servers` → RHDH `/api/mcp-actions/v1` |
| [`lightspeed-app-config.yaml`](../../manifests/gitops/developer-hub/lightspeed-app-config.yaml) | `lightspeed.mcpServers` token for LCS |

**Configure in `workshop.env`**

```bash
export MCP_TOKEN="your-long-random-token"   # optional; auto-generated if omitted
```

On first setup, if `MCP_TOKEN` is `changeme` or empty, `setup-developer-hub-lightspeed.sh` generates one and prints it — save it in `workshop.env` so re-runs keep the same token.

**Requirements**

- `LIGHTSPEED_ENABLED=true` and valid `OPENAI_API_KEY`
- Use a model that supports **tool calling** — `gpt-4o-mini` (default) or `gpt-4o`. Avoid legacy `gpt-4`.
- Re-run `./scripts/setup-developer-hub-config.sh` after enabling Lightspeed so MCP plugins and app-config merge are applied.
- Chat goes through the **Lightspeed UI** (sidebar or floating button). Use **`gpt-4o-mini`** — legacy **`gpt-4` does not support MCP tool calling**.
- **Start a new chat** after configuration changes; existing threads were created before MCP was wired and keep generic answers.
- Lightspeed settings (`mcp::backstage`) must be enabled — merged into the main app-config so the backend sends MCP headers.

**Example Lightspeed queries** (start a **new chat**, select `gpt-4o-mini`):

| Ask | What MCP should surface |
|-----|---------------------------|
| *Which software templates are available in this Developer Hub?* | Template entities (e.g. `quarkus-react-postgres`) |
| *List the components registered in the Software Catalog.* | Components such as `people-service` |
| *What is the people-service component?* | Catalog metadata, owner, links |
| *Which APIs are in the catalog?* | API entities (e.g. People REST API) |
| *What TechDocs are available for quarkus-workshop-guide?* | TechDocs content via MCP (when indexed) |

The chat UI also includes starter prompts **Software templates in this portal** and **People Service in the catalog** (configured in `lightspeed-app-config.yaml`).

**External MCP clients** (optional)

Point Cursor, Continue, or other MCP clients at:

- Streamable: `https://<rhdh-host>/api/mcp-actions/v1`
- SSE (legacy): `https://<rhdh-host>/api/mcp-actions/v1/sse`

Header: `Authorization: Bearer <MCP_TOKEN>`

**Verify MCP server**

```bash
RHDH_HOST=$(oc get route redhat-developer-hub -n "$RHDH_NAMESPACE" -o jsonpath='{.spec.host}')
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Bearer $MCP_TOKEN" \
  "https://${RHDH_HOST}/api/mcp-actions/v1"
```

A `401` means the endpoint exists but the token is wrong; `404` usually means MCP plugins are not loaded yet — re-run `./scripts/setup-developer-hub-config.sh`.

### Troubleshooting Developer Lightspeed

| Symptom | Fix |
|---------|-----|
| No chat button after config | Re-run `./scripts/setup-developer-hub-config.sh` with `LIGHTSPEED_ENABLED=true` |
| Chat errors / no response | Verify `OPENAI_API_KEY` in `workshop.env`; re-run `./scripts/setup-developer-hub-lightspeed.sh`. If logs show `${OPENAI_API_KEY}` literally, the secret was not substituted — re-run after updating `scripts/lib/common.sh` envsubst list |
| Model dropdown shows `llama-guard3:8b` | That is the safety/moderation model; with `LIGHTSPEED_SAFETY_GUARD=false` (default) chat uses OpenAI only. Pick `gpt-4o-mini` or another OpenAI model |
| `lightspeed-core` 500 on send | Usually failed Llama Guard moderation — re-run `./scripts/setup-developer-hub-lightspeed.sh` to apply `run-no-guard` config. If rollout hangs, delete stale ReplicaSets: `oc get rs -n $NAMESPACE \| grep redhat-developer-hub` |
| Chat ignores catalog / generic answers | Use **`gpt-4o-mini`** (not `gpt-4`); start a **new chat**; re-run `./scripts/setup-developer-hub-lightspeed.sh` |
| MCP skipped in LCS logs | Token file missing — re-run lightspeed setup; check `lightspeed-mcp-token` secret and `/var/secrets/mcp/token` mount on `lightspeed-core` |
| Permission denied in chat | Confirm `lightspeed-rbac-policies` and `RHDH_KEYCLOAK_USER` match your login |
| Plugins cache lock | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` |

See [Red Hat docs: Install and configure Developer Lightspeed](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/interacting_with_red_hat_developer_lightspeed_for_red_hat_developer_hub/install-and-configure_interacting-with-developer-lightspeed-for-rhdh).

## Ansible Automation Platform

The [Ansible Automation Platform plugin](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/integrating_with_red_hat_developer_hub/index) adds an **Ansible** sidebar entry (`/ansible`), connects to your Controller, and registers upstream Ansible software templates.

> **Full guide:** [06c — Ansible Automation Platform plugin](06c-ansible-automation-platform.md) (prerequisites, step-by-step setup, architecture, verification, troubleshooting).

### Quick start

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \
  --username admin \
  --password 'your-password' \
  --rh-registry-username <your-rh-registry-sa> \
  --rh-registry-token <your-rh-registry-token> \
  --apply
```

Or set manually in `scripts/workshop.env`:

```bash
export AAP_ENABLED=true
export AAP_CONTROLLER_URL=https://sandbox-aap-controller-<ns>.<router>   # optional; auto-detected
export AAP_TOKEN=<controller-personal-access-token>
export RH_REGISTRY_USERNAME=<rh-registry-service-account>
export RH_REGISTRY_TOKEN=<rh-registry-token>
export AAP_CHECK_SSL=false
```

Then:

```bash
./scripts/setup-developer-hub-config.sh
# or: ./scripts/setup-developer-hub-aap.sh
```

### Required variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AAP_ENABLED` | yes | Set to `true` to install Ansible dynamic plugins and merge app-config |
| `AAP_TOKEN` | yes | **Personal access token** from Controller (**User → Tokens**). Not the admin password |
| `RH_REGISTRY_USERNAME` | yes | [Red Hat registry service account](https://access.redhat.com/terms-based-registry/accounts) name |
| `RH_REGISTRY_TOKEN` | yes | Registry service account token — required for OCI plugin pulls |
| `AAP_CONTROLLER_URL` | recommended | Controller base URL. Auto-detected from `sandbox-aap-controller` route when empty |
| `AAP_CHECK_SSL` | no | Verify Controller TLS cert. Default `false` for sandbox |

See [06c-ansible-automation-platform.md](06c-ansible-automation-platform.md) for optional variables, PAT creation, sandbox AAP notes, and full troubleshooting.

### What gets installed

| Artifact | Purpose |
|----------|---------|
| [`dynamic-plugins-aap.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-aap.yaml) | Frontend `/ansible` plugin + scaffolder backend module (OCI from `registry.redhat.io`) |
| [`app-config-aap-snippet.yaml`](../../manifests/gitops/developer-hub/app-config-aap-snippet.yaml) | `ansible.rhaap` Controller connection + Ansible template catalog location |
| [`setup-developer-hub-aap.sh`](../../scripts/setup-developer-hub-aap.sh) | Registry pull secret, dev-tools sidecar, optional PAT auto-creation |
| `redhat-developer-hub-dynamic-plugins-registry-auth` | `auth.json` for OCI plugin pulls |
| `ansible-devtools-server` sidecar | Local creator service on port 8000 for Ansible templates |

After rollout, open **Ansible** in the sidebar or visit `/ansible`.

### Troubleshooting (summary)

| Symptom | Fix |
|---------|-----|
| `Init:CrashLoopBackOff` / registry unauthorized | Set `RH_REGISTRY_USERNAME` / `RH_REGISTRY_TOKEN` |
| Ansible page empty / API errors | Verify `AAP_CONTROLLER_URL` and `AAP_TOKEN` (PAT, not password) |
| Software templates fail | Ensure `ansible-devtools-server` sidecar is running |
| AAP sandbox 503 | Confirm `sandbox-aap` pods are running |

Full troubleshooting table: [06c-ansible-automation-platform.md § Troubleshooting](06c-ansible-automation-platform.md#troubleshooting).

## Authentication (Keycloak)

Developer Hub uses the shared Keycloak `workshop` realm:

| Variable | Default | Description |
|----------|---------|-------------|
| `RHDH_KEYCLOAK_CLIENT_ID` | `developer-hub` | Confidential OIDC client in Keycloak |
| `RHDH_KEYCLOAK_CLIENT_SECRET` | `developer-hub-workshop-secret` | Client secret |
| `RHDH_KEYCLOAK_USER` | `devhub` | Workshop Developer Hub login |
| `RHDH_KEYCLOAK_PASSWORD` | `r#dh@t` | Workshop Developer Hub password |

`setup-developer-hub-config.sh`:

1. Ensures the `developer-hub` client and `devhub` user exist in Keycloak
2. Configures Kubernetes/Topology cluster access (`setup-developer-hub-kubernetes.sh`)
3. Patches Developer Hub app-config with OIDC provider settings
4. Enables Kubernetes, Topology, Tech Radar, and (optionally) Developer Lightspeed and Ansible dynamic plugins
5. Mounts `RHDH_OIDC_CLIENT_SECRET` into the backend pod
6. Restarts Developer Hub (Lightspeed sidecars when `LIGHTSPEED_ENABLED=true`; Ansible setup when `AAP_ENABLED=true`)

## Catalog, OpenAPI, and Tech Radar

After install, run:

```bash
./scripts/configure-developer-hub-catalog.sh
```

This deploys the **workshop catalog server** (serves entities, OpenAPI, Tech Radar data) and registers the **People REST API** in the catalog. See [07-developer-hub-catalog](07-developer-hub-catalog.md).

## Access Developer Hub

```bash
RHDH_HOST=$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')
echo "https://${RHDH_HOST}"
echo "APIs:    https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
echo "Radar:   https://${RHDH_HOST}/tech-radar"
```

Sign in with Keycloak user **`devhub` / `r#dh@t`**.

> **Important:** The password uses a **`#`** (hash), not **`3`**.  
> `r#dh@t` is correct — `r3dh@t` will fail (that password is for `admin` and `user`).

## TLS note

`NODE_TLS_REJECT_UNAUTHORIZED=0` is set on the Backstage CR for PoC clusters with self-signed certificates. Remove for production.

## Restart after config changes

```bash
./scripts/setup-developer-hub-config.sh
./scripts/configure-developer-hub-catalog.sh
```

Ensure the persistent plugins cache is enabled first (one-time):

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
```

Without the cache, each restart re-downloads all dynamic plugins.

## Repair Keycloak login failures

If sign-in shows "Application is not available", Keycloak is likely scaled to zero:

```bash
./scripts/repair-keycloak.sh
```

## Next step

[Catalog, template, and integrations](07-developer-hub-catalog.md)
