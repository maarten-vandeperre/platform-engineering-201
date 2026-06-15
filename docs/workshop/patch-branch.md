# Patch an existing workshop (branch upgrade)

Use this when you **already ran bootstrap** on one branch (e.g. `20260613-initial-version`) and **checked out a feature branch** that adds Developer Hub capabilities — without reinstalling the whole stack.

> **Do not run `./scripts/bootstrap-workshop.sh` again** unless you want a full wipe and reinstall. Bootstrap redeploys Keycloak, People Service, RHDH Helm, catalog, orchestrator, and more. Branch upgrades only need targeted scripts.

## Example: enable Lightspeed + MCP

Branch: `20260613-enable-lightspeed-and-mcp` (or similar)

Adds:

- **Developer Lightspeed** — AI chat (`/lightspeed`, floating spark button)
- **MCP** — catalog- and TechDocs-aware tools for Lightspeed chat

Deep dive: [06-install-developer-hub — Developer Lightspeed](06-install-developer-hub.md#developer-lightspeed)

---

## Prerequisites

- Workshop already running from the base branch (Developer Hub pod **Ready**)
- `oc` logged in to the same namespace as before
- Checked out the feature branch locally:

```bash
git checkout 20260613-enable-lightspeed-and-mcp
git pull
```

---

## Step 1 — Update `scripts/workshop.env`

Edit the file (do not only `export` in the shell — scripts read the file on disk).

Add or change:

```bash
export LIGHTSPEED_ENABLED=true
export OPENAI_API_KEY=sk-...              # required — OpenAI platform key
export OPENAI_MODEL=gpt-4o-mini           # recommended; supports MCP tool calling
export LIGHTSPEED_VLLM_MAX_TOKENS=4096    # optional
export LIGHTSPEED_SAFETY_GUARD=false      # default; OpenAI-only workshop

# Optional — shared token for MCP server + Lightspeed client (auto-generated if changeme)
# export MCP_TOKEN=your-long-random-token
```

Keep your existing values (`WORKSHOP_NAMESPACE`, `CLUSTER_ROUTER_BASE`, GitHub tokens, etc.) unchanged unless you moved clusters.

See [02-configuration.md](02-configuration.md) for the full variable table.

### Reload env in your shell (optional)

If you `source scripts/workshop.env` in the same terminal, unset stale vars first or open a **new terminal** — see [TUTORIAL Module 1](TUTORIAL.md#module-1--local-tools-and-repository-fork).

---

## Step 2 — Apply Developer Hub changes

One command applies app-config, dynamic plugins (Lightspeed + MCP), and sidecars:

```bash
chmod +x scripts/*.sh scripts/lib/*.sh   # if needed after checkout
./scripts/setup-developer-hub-config.sh
```

That script:

1. Merges **MCP** and **Lightspeed** snippets into app-config
2. Adds **dynamic-plugins-lightspeed.yaml** and **dynamic-plugins-mcp.yaml** to the plugins ConfigMap
3. Restarts Developer Hub
4. Runs **`setup-developer-hub-lightspeed.sh`** (Llama Stack, Lightspeed Core sidecars, secrets, MCP token)

### Alternative — Lightspeed only

If you already ran config and only changed env or sidecar manifests:

```bash
./scripts/setup-developer-hub-lightspeed.sh --force-rollout
```

---

## Step 3 — Verify

| Check | How |
|-------|-----|
| Lightspeed UI | Sign in to Developer Hub → **Lightspeed** in sidebar or `/lightspeed` |
| Model | Choose **`gpt-4o-mini`** (legacy `gpt-4` does not support MCP tools) |
| New chat | **Start a new conversation** — old threads were created before MCP was wired |
| MCP endpoint | `curl -sk -H "Authorization: Bearer $MCP_TOKEN" "https://<rhdh-host>/api/mcp-actions/v1"` — expect JSON, not `404` |
| Full stack | `./scripts/validate-workshop.sh` |

If `MCP_TOKEN` was auto-generated, save the printed value into `workshop.env` so the next re-run keeps the same token.

---

## What is *not* required

| Action | Needed for Lightspeed/MCP patch? |
|--------|----------------------------------|
| `./scripts/bootstrap-workshop.sh` | No |
| `./scripts/cleanup-workshop.sh` | No |
| `./scripts/deploy-people-app.sh` | No |
| `./scripts/setup-keycloak.sh` | No |
| `./scripts/configure-developer-hub-catalog.sh` | No (unless catalog changed on the branch) |

---

## When to run bootstrap again

| Scenario | Action |
|----------|--------|
| Add Lightspeed/MCP to existing install | This guide — `setup-developer-hub-config.sh` |
| Fresh namespace / demo reset | `./scripts/cleanup-workshop.sh --yes` then `./scripts/bootstrap-workshop.sh` |
| Switched OpenShift cluster | Update `workshop.env` (`CLUSTER_ROUTER_BASE`, clear `KEYCLOAK_URL`), then bootstrap or phased repair |
| Branch also changes People app / Keycloak manifests | Run the specific script for that layer (see branch README or diff), not full bootstrap unless many layers changed |

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `LIGHTSPEED_ENABLED is not true; skipping` | Set `LIGHTSPEED_ENABLED=true` in **`scripts/workshop.env`**, not only in the shell |
| `OPENAI_API_KEY is still 'changeme'` | Add a valid key to `workshop.env`, re-run config script |
| No Lightspeed in sidebar | Re-run `./scripts/setup-developer-hub-config.sh`; wait for pod Ready |
| Chat works but no catalog answers | New chat + `gpt-4o-mini`; verify MCP plugins loaded (`404` on `/api/mcp-actions/v1` → re-run config) |
| Empty chat bubbles (no text) | MCP token mismatch between app-config and Lightspeed sidecar — set `export MCP_TOKEN=...` in `workshop.env` and re-run `./scripts/setup-developer-hub-config.sh`; use **gpt-4o-mini** (not gpt-5-pro) |
| `install-dynamic-plugins` slow | One-time; `./scripts/setup-developer-hub-dynamic-plugins-cache.sh` if not already done |
| `ProgressDeadlineExceeded` or init stuck on `Waiting for lock release` | Old pod still on ephemeral plugins volume while new pod uses PVC — scripts now scale to 0 first; manual fix: `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` then `./scripts/setup-developer-hub-lightspeed.sh --force-rollout` |
| Helm / deployment errors after long idle | `./scripts/repair-developer-hub.sh` — not a branch patch issue |

More detail: [08-validation.md](08-validation.md) and [06-install-developer-hub.md](06-install-developer-hub.md#developer-lightspeed).

---

## General pattern for other feature branches

1. `git checkout <feature-branch>`
2. Read the diff under `manifests/gitops/developer-hub/` and `scripts/`
3. Add new variables to `scripts/workshop.env`
4. Run the **smallest script** that owns that layer:

| Layer | Typical script |
|-------|----------------|
| Developer Hub app-config / plugins | `./scripts/setup-developer-hub-config.sh` |
| Lightspeed sidecars | `./scripts/setup-developer-hub-lightspeed.sh` |
| Catalog / Tech Radar | `./scripts/configure-developer-hub-catalog.sh` |
| Orchestrator | `./scripts/setup-orchestrator.sh` |
| People app | `./scripts/deploy-people-app.sh` or `./scripts/repair-people-app.sh` |
| Full reset | `./scripts/cleanup-workshop.sh` + `./scripts/bootstrap-workshop.sh` |
