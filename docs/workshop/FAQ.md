# Workshop FAQ

Common questions and fixes when bootstrapping **Red Hat Developer Hub** on OpenShift sandbox or Dev Spaces.

For automated checks, see [08-validation.md](08-validation.md). For repair script index, see the **Repair scripts** table there.

---

## Bootstrap and rollouts

### Can a Developer Hub rollout really take 30 minutes?

**Sometimes on first install**, yes — especially with `AAP_ENABLED=true`, `LIGHTSPEED_ENABLED=true`, and a fresh dynamic-plugins PVC. The scripts allow up to **30 minutes** when Ansible OCI plugins are enabled.

**Typical timings when things are healthy:**

| Step | First install | Later restarts (plugins cached on PVC) |
|------|---------------|----------------------------------------|
| `install-dynamic-plugins` | 5–15 min | 1–3 min |
| `init-rag-data` (Lightspeed) | ~1–2 min | ~1–2 min |
| Sidecars (`llama-stack`, `lightspeed-core`) | 2–5 min | 2–5 min |

If you exceed ~20 minutes with **no change** in pod status, something is probably stuck — check logs (see below).

### Why do I see “Ansible dynamic plugins are downloading” several times?

Bootstrap **restarts Developer Hub more than once** (Helm install, PVC cache setup, config apply). Each restart prints a wait message.

On **later restarts**, when plugins are already on the PVC, you should see a generic message like *“Rolling out Developer Hub…”* instead. If you still see the Ansible download hint on every restart, pull the latest scripts (`git pull`).

### Progress says `init-rag-data` for 20+ minutes — is Lightspeed that slow?

**Usually no.** `init-rag-data` only copies RAG files from an image (~1–2 minutes). If it appears stuck for many minutes, the **first** init container (`install-dynamic-plugins`) is often still running.

Check which init container is active:

```bash
oc get pod -n "$WORKSHOP_NAMESPACE" -l app.kubernetes.io/name=developer-hub \
  -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{"\t"}{.state}{"\n"}{end}'
oc logs -n "$WORKSHOP_NAMESPACE" -l app.kubernetes.io/name=developer-hub \
  -c install-dynamic-plugins --tail=30
```

### `install-dynamic-plugins` logs: “Waiting for lock release”

Another pod (or a crashed prior install) left a lock on the `dynamic-plugins-root` PVC.

**Fix:**

```bash
oc scale deployment/redhat-developer-hub -n "$WORKSHOP_NAMESPACE" --replicas=0
# wait until no Developer Hub pods remain
./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock
./scripts/setup-developer-hub-config.sh
```

Or: `./scripts/repair-developer-hub.sh`

### `timed out waiting for the condition` during rollout

On sandbox, slow plugin install can hit Helm’s wait timeout. Newer scripts use a friendly poller that **warns and continues** if pods look healthy but the deadline passed.

If the pod is in **CrashLoopBackOff** or **ImagePullBackOff**, increasing the timeout will not help — fix the underlying error (often registry auth; see below).

---

## Red Hat Container Registry (Ansible plugins)

### What are `RH_REGISTRY_USERNAME` and `RH_REGISTRY_TOKEN`?

When `AAP_ENABLED=true`, Developer Hub pulls **Ansible OCI dynamic plugins** from `registry.redhat.io` during `install-dynamic-plugins`.

Create a **Red Hat Container Registry service account** (not the same as AAP login or `oc` token):

https://access.redhat.com/terms-based-registry/accounts

Open the **Token Information** tab and copy:

```bash
export RH_REGISTRY_USERNAME='11009103|my-service-account-name'   # full username from the portal
export RH_REGISTRY_TOKEN='eyJhbGci...'                           # JWT from the same tab — this is normal
```

### The token is a JWT — is that wrong?

**No.** Registry service account tokens from the Token Information tab **are JWTs** (`eyJ…`). That is expected.

**Do not** use OpenShift service account tokens shaped like `namespace:eyJ…` — those fail plugin install.

### `skopeo login failed` or live check failed in Dev Spaces

The workspace shell may not reach `registry.redhat.io` even when the **cluster** can. Newer scripts fall back to curl OAuth checks and may **apply credentials with a warning**.

If validation still blocks you:

```bash
export RH_REGISTRY_SKIP_LIVE_VALIDATION=true   # in workshop.env
```

Then re-run `./scripts/setup-developer-hub-aap.sh --force-rollout` and confirm on the cluster:

```bash
oc logs -n "$WORKSHOP_NAMESPACE" -l app.kubernetes.io/name=developer-hub \
  -c install-dynamic-plugins --tail=50
```

### `install-dynamic-plugins` CrashLoopBackOff — “Please login to the Red Hat Registry”

Registry secret missing or wrong credentials on the cluster.

```bash
source scripts/workshop.env
./scripts/setup-developer-hub-aap.sh --force-rollout
```

Ensure `RH_REGISTRY_USERNAME` includes the numeric prefix and pipe (e.g. `11009103|my-sa-name`).

---

## Routes and URLs

### “Application is not available” in the browser but pods are Running

You are likely on the **wrong hostname or cluster**. Always use the route from OpenShift:

```bash
oc get route redhat-developer-hub -n "$WORKSHOP_NAMESPACE" \
  -o jsonpath='https://{.spec.host}{"\n"}'
```

Do not reuse a URL from another namespace, another user’s sandbox, or a bookmark from a different cluster (e.g. `sandbox600` vs `rm1`).

### Validation shows `HTTP 000` for Developer Hub OIDC

`HTTP 000` means curl could not reach the route **from the shell** (Dev Spaces egress, wrong cluster context). It is often a **warning**, not a failed deployment. Sign in via the browser using the route from `oc get route`.

---

## Developer Hub configuration

### Catalog, theme, or plugins disappeared after Helm upgrade

Helm can overwrite the app-config ConfigMap with minimal values if `appConfig` is embedded in Helm values. Workshop config must come from `./scripts/setup-developer-hub-config.sh`.

**Repair:**

```bash
./scripts/setup-developer-hub-config.sh
```

After a manual `helm upgrade`, always run the config script. `./scripts/install-developer-hub-helm.sh` re-applies workshop config automatically on recent script versions.

### Sign-in popup: “authentication requires session support”

Missing `auth.session.secret` in app-config (often after Helm overwrote config).

```bash
./scripts/setup-developer-hub-config.sh
```

---

## GitHub plugins (Issues, Actions, Scaffolder)

### GitHub Authorize popup: “Invalid Redirect URI”

Add this **exact** callback URL to your GitHub OAuth App (Settings → Developer settings → OAuth Apps):

```text
https://<your-rhdh-host>/api/auth/github/handler/frame
```

Get the host from:

```bash
oc get route redhat-developer-hub -n "$WORKSHOP_NAMESPACE" -o jsonpath='{.spec.host}'
```

You must update the callback when **`WORKSHOP_NAMESPACE` or cluster** changes. Print the URL anytime:

```bash
./scripts/setup-github-auth.sh --oauth-only --no-apply
```

---

## Dev Spaces and scripts

### `ModuleNotFoundError: No module named 'yaml'`

Dev Spaces UDI has Python but not PyYAML. Bootstrap scripts auto-install it (`dnf install python3-pyyaml` or pip). Run:

```bash
bash devfile/install-tools.sh
```

### `ensure_all_workshop_instances: command not found`

Pull the latest `main` — helper functions live in `scripts/lib/common.sh`.

---

## Quick reference

| Symptom | First command to try |
|---------|----------------------|
| Stuck on plugin lock | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` |
| Registry / Ansible init failure | `./scripts/setup-developer-hub-aap.sh --force-rollout` |
| Empty catalog / missing config | `./scripts/setup-developer-hub-config.sh` |
| Full stack idle / scaled down | `./scripts/ensure-workshop-platform.sh` |
| Everything misbehaving | `./scripts/repair-developer-hub.sh` |
| Validate end-to-end | `./scripts/validate-workshop.sh` |
