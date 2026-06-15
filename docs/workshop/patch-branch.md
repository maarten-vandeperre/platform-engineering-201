# Patch an existing workshop (branch upgrade)

Use this when you **already ran bootstrap** and want to apply a **feature branch** without reinstalling the whole stack.

> **Do not run `./scripts/bootstrap-workshop.sh` again** unless you want a full wipe. Bootstrap redeploys Keycloak, People Service, RHDH Helm, catalog, orchestrator, and more. Branch upgrades only need targeted scripts.

## Typical upgrade path

```text
20260613-initial-version
        │
        ▼  LIGHTSPEED_ENABLED + setup-developer-hub-config.sh
20260613-enable-lightspeed-and-mcp
        │
        ▼  AAP_* + RH_REGISTRY_* + setup-developer-hub-config.sh   ← you are here
20260614-enable-ansible
```

If you already have **Lightspeed + MCP** working, keep those `workshop.env` values and add the Ansible variables below. You do **not** need to re-run bootstrap or disable Lightspeed.

---

## Current branch: Ansible Automation Platform

Branch: `20260614-enable-ansible` (from `20260613-enable-lightspeed-and-mcp`)

Adds on top of Lightspeed/MCP:

| Feature | Route / UI | Purpose |
|---------|------------|---------|
| **Upstream AAP plugin** | `/ansible` | Controller integration, Ansible software templates |
| **Custom AAP Management plugin** (optional) | `/aap-management` | Paginated templates, launch jobs, run history |

Deep dive: [06c — Ansible Automation Platform](06c-ansible-automation-platform.md)

---

## Prerequisites

- Workshop running with Developer Hub pod **Ready**
- **Lightspeed/MCP** already applied (or enable both in the same `workshop.env` pass)
- `oc` logged in to the same namespace as before
- Checked out the branch:

```bash
git checkout 20260614-enable-ansible
git pull
```

- **Red Hat Container Registry** service account — required to pull OCI Ansible dynamic plugins from `registry.redhat.io` ([create one](https://access.redhat.com/terms-based-registry/accounts))
- **AAP Controller** reachable from the Developer Hub pod (local `sandbox-aap` route or external workshop AAP URL)
- **Controller personal access token (PAT)** — create under **User → Tokens** in the Controller UI, or let scripts mint one from admin credentials

Optional but recommended before the first Ansible plugin install (long `install-dynamic-plugins` run):

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh
```

---

## Step 1 — Update `scripts/workshop.env`

Edit the file on disk (scripts read the file; shell `export` alone is not enough).

### Keep from the Lightspeed branch

Do **not** remove these if Lightspeed should stay enabled:

```bash
export LIGHTSPEED_ENABLED=true
export OPENAI_API_KEY=sk-...
export OPENAI_MODEL=gpt-4o-mini
export MCP_TOKEN=<same token as before>   # if you saved it from the Lightspeed patch
```

### Add for Ansible

**Minimum (upstream `/ansible` plugin):**

```bash
export AAP_ENABLED=true
export AAP_CONTROLLER_URL=https://sandbox-aap-controller-<ns>.<router>   # or external workshop URL
export AAP_TOKEN=<controller-pat>
export AAP_CHECK_SSL=false

export RH_REGISTRY_USERNAME=<rh-registry-service-account>
export RH_REGISTRY_TOKEN=<rh-registry-token>
```

**Custom AAP Management plugin (`/aap-management`) — required separately:**

The upstream `/ansible` plugin and the workshop **custom** plugin are controlled by **different** flags. `AAP_ENABLED=true` alone does **not** install `/aap-management`.

```bash
export AAP_MANAGEMENT_ENABLED=true
```

Uses the same `AAP_CONTROLLER_URL`, `AAP_TOKEN`, and `AAP_CHECK_SSL` as above.

**Optional — only used when `AAP_TOKEN=changeme` (auto mint PAT):**

```bash
export AAP_ADMIN_USERNAME=admin
export AAP_ADMIN_PASSWORD=<aap-admin-password>
```

See [02-configuration.md](02-configuration.md) for the full variable table.

### Helper — populate AAP variables automatically

Recommended when using sandbox AAP or a known Controller URL:

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://sandbox-aap-controller-<your-namespace>.<router> \
  --username admin \
  --password 'your-aap-password' \
  --rh-registry-username <rh-registry-sa> \
  --rh-registry-token <rh-registry-token>
```

Add `--apply` to run `./scripts/setup-developer-hub-aap.sh` immediately (registry secret + dev-tools sidecar only). You still need **Step 2** to merge app-config and dynamic plugins.

External workshop AAP (not local `sandbox-aap`):

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://aap-aap.apps.<workshop-cluster>.redhatworkshops.io \
  --username admin \
  --password 'your-password' \
  --rh-registry-username <rh-registry-sa> \
  --rh-registry-token <rh-registry-token>
```

Reload env in a new terminal or `unset` stale exports before sourcing — see [TUTORIAL Module 1](TUTORIAL.md#module-1--local-tools-and-repository-fork).

---

## Step 2 — Apply Developer Hub changes (main command)

```bash
chmod +x scripts/*.sh scripts/lib/*.sh   # if needed after checkout
./scripts/setup-developer-hub-config.sh
```

This is the **one script you need** after `workshop.env` is updated. When `AAP_ENABLED=true` (and optional `AAP_MANAGEMENT_ENABLED=true`), it:

1. Keeps **Lightspeed + MCP** app-config and dynamic plugins (if still enabled)
2. Merges **AAP** app-config and `dynamic-plugins-aap.yaml`
3. Builds and publishes the **custom AAP Management** plugin (if enabled)
4. Calls **`setup-developer-hub-aap.sh`** (registry auth, `ansible-devtools-server` sidecar, rollout)
5. Calls **`setup-developer-hub-lightspeed.sh`** when `LIGHTSPEED_ENABLED=true`

Expect a **long rollout** the first time Ansible OCI plugins are downloaded (several minutes). The pod may show multiple containers when Lightspeed and Ansible sidecars are both enabled.

### Layer-specific scripts (only if you changed one layer)

| Layer | Script |
|-------|--------|
| Ansible registry + dev-tools sidecar only | `./scripts/setup-developer-hub-aap.sh --force-rollout` |
| Custom AAP Management plugin only | `./scripts/setup-custom-aap-management-plugin.sh` |
| Lightspeed sidecars only | `./scripts/setup-developer-hub-lightspeed.sh --force-rollout` |
| AAP env only (no RHDH merge) | `./scripts/configure-aap-workshop-env.sh …` |

---

## Step 3 — Verify

| Check | How |
|-------|-----|
| Pod ready | `oc get pod -n $RHDH_NAMESPACE -l app.kubernetes.io/name=developer-hub` — expect **Ready** with multiple containers |
| Ansible plugins installed | `oc logs -l app.kubernetes.io/name=developer-hub -c install-dynamic-plugins \| grep -i ansible` |
| **Ansible** UI | Sign in → sidebar **Ansible** or `/ansible` |
| **AAP Management** (optional) | Sidebar **AAP Templates** or `/aap-management` |
| Lightspeed still works | `/lightspeed`, new chat, model **gpt-4o-mini** |
| MCP | `curl -sk -H "Authorization: Bearer $MCP_TOKEN" "https://<rhdh-host>/api/mcp-actions/v1"` |
| Full stack | `./scripts/validate-workshop.sh` |

---

## What is *not* required

| Action | Needed for Ansible patch from Lightspeed branch? |
|--------|--------------------------------------------------|
| `./scripts/bootstrap-workshop.sh` | No |
| `./scripts/cleanup-workshop.sh` | No |
| `./scripts/deploy-people-app.sh` | No |
| `./scripts/setup-keycloak.sh` | No |
| `./scripts/configure-developer-hub-catalog.sh` | No (unless catalog changed on the branch) |
| Re-run Lightspeed-only script alone | No — `setup-developer-hub-config.sh` includes Lightspeed when enabled |

---

## When to run bootstrap again

| Scenario | Action |
|----------|--------|
| Add Ansible (or Lightspeed) to existing install | This guide — `setup-developer-hub-config.sh` |
| Fresh namespace / demo reset | `./scripts/cleanup-workshop.sh --yes` then `./scripts/bootstrap-workshop.sh` |
| Switched OpenShift cluster | Update `workshop.env` (`CLUSTER_ROUTER_BASE`, clear `KEYCLOAK_URL`), then bootstrap or phased repair |
| Branch also changes People app / Keycloak | Run the script for that layer only |

---

## Troubleshooting

### Ansible

| Symptom | Fix |
|---------|-----|
| Init container: `Please login to the Red Hat Registry` | Set `RH_REGISTRY_USERNAME` / `RH_REGISTRY_TOKEN` in **`workshop.env`**, then re-run `./scripts/setup-developer-hub-config.sh` (registry secret is applied **before** rollout) |
| Rollout timed out / `Init:CrashLoopBackOff` on `install-dynamic-plugins` | Usually missing registry auth when `AAP_ENABLED=true` — see row above; first Ansible OCI install can take **15–30 minutes** |
| No **Ansible** sidebar | Confirm `AAP_ENABLED=true` in **`workshop.env`**; check init container logs |
| **AAP Templates** / `/aap-management` missing | `AAP_ENABLED` does not install the custom plugin — set **`AAP_MANAGEMENT_ENABLED=true`** and re-run `./scripts/setup-developer-hub-config.sh` |
| Ansible page empty / API errors | Set `AAP_CONTROLLER_URL` to the **controller** route; use PAT in `AAP_TOKEN`, not admin password |
| SSL errors to Controller | `export AAP_CHECK_SSL=false` |
| Software templates fail | Keep `AAP_CREATOR_SERVICE_ENABLED=true`; confirm container `ansible-devtools-server` in pod |
| `ProgressDeadlineExceeded` / init lock | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` then re-run config script |

More: [06c-ansible-automation-platform.md — Troubleshooting](06c-ansible-automation-platform.md#troubleshooting)

### Lightspeed + MCP (unchanged from previous branch)

| Symptom | Fix |
|---------|-----|
| Empty chat bubbles | MCP token mismatch — set `MCP_TOKEN` in `workshop.env`, re-run `./scripts/setup-developer-hub-config.sh`; use **gpt-4o-mini** |
| `OPENAI_API_KEY is still 'changeme'` | Add valid key to `workshop.env` |
| Chat works but no catalog answers | **New chat** + `gpt-4o-mini`; verify MCP endpoint returns tools, not `404` |

More: [08-validation.md](08-validation.md) and [06-install-developer-hub.md — Developer Lightspeed](06-install-developer-hub.md#developer-lightspeed)

---

## Appendix — Lightspeed + MCP only (from initial branch)

If you skipped the Lightspeed branch and jumped here from `20260613-initial-version`, enable both in `workshop.env`:

```bash
export LIGHTSPEED_ENABLED=true
export OPENAI_API_KEY=sk-...
export OPENAI_MODEL=gpt-4o-mini
export AAP_ENABLED=true
# … plus AAP and RH_REGISTRY_* as above
```

Then run:

```bash
./scripts/setup-developer-hub-config.sh
```

See [06-install-developer-hub — Developer Lightspeed](06-install-developer-hub.md#developer-lightspeed) for Lightspeed-only details.

---

## Script reference

| Layer | Script |
|-------|--------|
| **All-in-one (recommended)** | `./scripts/setup-developer-hub-config.sh` |
| AAP env helper | `./scripts/configure-aap-workshop-env.sh` |
| Ansible registry + sidecar | `./scripts/setup-developer-hub-aap.sh` |
| Custom AAP Management plugin | `./scripts/setup-custom-aap-management-plugin.sh` |
| Lightspeed sidecars | `./scripts/setup-developer-hub-lightspeed.sh` |
| Dynamic plugins PVC / lock | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh` |
| Catalog / Tech Radar | `./scripts/configure-developer-hub-catalog.sh` |
| Full reset | `./scripts/cleanup-workshop.sh` + `./scripts/bootstrap-workshop.sh` |
