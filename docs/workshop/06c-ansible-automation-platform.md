# Ansible Automation Platform plugin for Developer Hub

> **Parent module:** [06 — Install Developer Hub](06-install-developer-hub.md)  
> **Configuration reference:** [02 — Configure the workshop](02-configuration.md#ansible-automation-platform-aap)

The [Ansible Automation Platform (AAP) plugin](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/integrating_with_red_hat_developer_hub/index) connects Red Hat Developer Hub to your **Automation Controller**. It adds an **Ansible** sidebar entry (`/ansible`), surfaces jobs and templates from Controller, and registers upstream Ansible software templates in the catalog.

This workshop ships scripts and manifests so you can enable the plugin with a few `workshop.env` variables and `./scripts/setup-developer-hub-config.sh`.

---

## What you get

| Feature | Description |
|---------|-------------|
| **Ansible page** | Sidebar link and route at `/ansible` |
| **Controller integration** | Jobs, inventories, and automation content from your AAP Controller |
| **Software templates** | Ansible playbook/collection templates from [ansible-rhdh-templates](https://github.com/ansible/ansible-rhdh-templates) |
| **Scaffolder backend** | Backend module to provision Ansible projects via Developer Hub templates |

---

## Prerequisites

Before enabling the plugin, you need:

1. **Red Hat Developer Hub** installed and configured (`./scripts/setup-developer-hub-config.sh` at least once).
2. **Ansible Automation Platform Controller** reachable from the Developer Hub pod.
   - OpenShift Developer Sandbox often includes a `sandbox-aap` instance in the same namespace.
   - Confirm routes exist: `oc get route -n $WORKSHOP_NAMESPACE | grep sandbox-aap`
3. **Controller personal access token (PAT)** — not the admin password.
4. **Red Hat Container Registry credentials** — required to pull OCI dynamic plugins from `registry.redhat.io`.
   - Create a [registry service account](https://access.redhat.com/terms-based-registry/accounts).
   - Without registry auth, the `install-dynamic-plugins` init container fails and Developer Hub will not start.

Optional but recommended for Ansible software templates:

5. **Persistent dynamic plugins cache** — speeds up restarts after the first successful plugin install:

   ```bash
   ./scripts/setup-developer-hub-dynamic-plugins-cache.sh
   ```

---

## Architecture

```text
Developer Hub pod
├── initContainer: install-dynamic-plugins
│     └── pulls OCI plugins from registry.redhat.io (needs RH_REGISTRY_* auth)
├── container: backstage-backend
│     ├── ansible-backstage-plugin-catalog-backend-module-rhaap  ← syncs Controller projects into catalog
│     └── reads app-config: ansible.rhaap.baseUrl + token
├── container: ansible-devtools-server  (optional sidecar)
│     └── adt server on 127.0.0.1:8000 — Ansible template creator service
└── …

app-config (merged when AAP_ENABLED=true)
├── ansible.rhaap.baseUrl     → AAP Controller URL
├── ansible.rhaap.token       → Controller PAT
├── ansible.creatorService    → 127.0.0.1:8000 (local dev-tools sidecar)
├── catalog.providers.rhaap   → sync orgs/users/teams and job templates from Controller
└── catalog.locations         → ansible-rhdh-templates on GitHub

External
└── AAP Controller API  ← PAT auth (User → Tokens)
```

**Important:** `AAP_ADMIN_USERNAME` / `AAP_ADMIN_PASSWORD` are **not** sent to the plugin. They are only used by `setup-developer-hub-aap.sh` to auto-create a PAT when `AAP_TOKEN=changeme`. The plugin always uses `AAP_TOKEN`.

---

## Configure `scripts/workshop.env`

Copy from the example file if you have not already:

```bash
cp scripts/workshop.env.example scripts/workshop.env
```

### Required variables

| Variable | Example | Description |
|----------|---------|-------------|
| `AAP_ENABLED` | `true` | Enables Ansible dynamic plugins and merges AAP app-config |
| `AAP_TOKEN` | *(long token string)* | Controller **personal access token** — create under **User → Tokens** in the Controller UI |
| `RH_REGISTRY_USERNAME` | `12345678` | Red Hat registry service account name |
| `RH_REGISTRY_TOKEN` | *(token)* | Registry service account token |

### Recommended variables

| Variable | Example | Description |
|----------|---------|-------------|
| `AAP_CONTROLLER_URL` | `https://sandbox-aap-controller-<ns>.<router>` | Controller base URL. **Auto-detected** from route `sandbox-aap-controller` in `WORKSHOP_NAMESPACE` when empty |
| `AAP_CHECK_SSL` | `false` | Verify Controller TLS certificate. Use `false` for sandbox clusters with edge routes |

### Optional variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AAP_ADMIN_USERNAME` | `admin` | Used only when `AAP_TOKEN=changeme` to mint a PAT via Controller API |
| `AAP_ADMIN_PASSWORD` | `changeme` | Admin password for PAT auto-creation |
| `AAP_CREATOR_SERVICE_ENABLED` | `true` | Add `ansible-devtools-server` sidecar for Ansible software templates |
| `AAP_DEVTOOLS_IMAGE` | `registry.redhat.io/ansible-automation-platform-25/ansible-dev-tools-rhel8:latest` | Image for the dev-tools sidecar |
| `RH_REGISTRY_PULL_SECRET` | *(empty)* | Name of an existing OpenShift `dockerconfigjson` secret to extract `registry.redhat.io` auth instead of username/token |
| `AAP_AUTOMATION_HUB_URL` | — | Reserved for future Hub integration (not merged by default) |
| `AAP_DEVSPACES_URL` | — | Reserved for future Dev Spaces integration (not merged by default) |

### Full example (`scripts/workshop.env`)

```bash
# Enable Ansible plugin
export AAP_ENABLED=true

# Controller — auto-detected on sandbox if route sandbox-aap-controller exists
export AAP_CONTROLLER_URL=https://sandbox-aap-controller-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com

# Personal access token from Controller UI (User → Tokens)
export AAP_TOKEN=your-controller-pat-here

# Sandbox TLS — edge routes often use certs the plugin should not strictly verify
export AAP_CHECK_SSL=false

# Red Hat Container Registry (required for OCI plugin install)
export RH_REGISTRY_USERNAME=your-rh-registry-service-account
export RH_REGISTRY_TOKEN=your-rh-registry-token

# Optional: only needed if AAP_TOKEN=changeme and you want auto token creation
export AAP_ADMIN_USERNAME=admin
export AAP_ADMIN_PASSWORD=your-aap-admin-password

# Optional: disable dev-tools sidecar if you only want the /ansible UI
# export AAP_CREATOR_SERVICE_ENABLED=false
```

---

## Step-by-step setup

## External workshop AAP (not local sandbox-aap)

If your Controller is **not** the `sandbox-aap` instance in your OpenShift namespace (e.g. Red Hat Workshops shared AAP), set the URL **explicitly**. Auto-detection only applies when `AAP_CONTROLLER_URL` is empty.

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://aap-aap.apps.cluster-w7kvs-1.dynamic2.redhatworkshops.io \
  --username admin \
  --password 'your-workshop-password' \
  --rh-registry-username <your-rh-registry-sa> \
  --rh-registry-token <your-rh-registry-token> \
  --apply
```

Workshop AAP uses the **gateway** API at `/api/controller/v2/` on that URL (not the local `sandbox-aap-controller` route in your namespace).

**Recommended — one command (updates `workshop.env` and installs the plugin):**

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \
  --username admin \
  --password 'your-password' \
  --rh-registry-username <your-rh-registry-sa> \
  --rh-registry-token <your-rh-registry-token> \
  --apply
```

Replace `your-password` with your AAP admin password and the registry placeholders with your [Red Hat Container Registry](https://access.redhat.com/terms-based-registry/accounts) service account. The script resolves the Controller URL from the `sandbox-aap-controller` route when present (gateway `--url` is fine).

**AAP credentials only** (still need registry flags before `--apply`):

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \
  --username admin \
  --password 'your-password'
```

**Cluster auto-detect** (uses `sandbox-aap-controller` route + `sandbox-aap-admin-password` secret when available):

```bash
./scripts/configure-aap-workshop-env.sh
```

This script can set automatically from your cluster and admin credentials:

| Variable | Auto source |
|----------|-------------|
| `AAP_ENABLED` | set to `true` |
| `AAP_CONTROLLER_URL` | `sandbox-aap-controller` route or `--url` |
| `AAP_ADMIN_USERNAME` / `AAP_ADMIN_PASSWORD` | flags, `workshop.env`, or secret `sandbox-aap-admin-password` |
| `AAP_TOKEN` | minted via Controller API when AAP is running |
| `AAP_CHECK_SSL` | defaults to `false` |

**Cannot be derived from AAP console URL + admin password:**

| Variable | Why |
|----------|-----|
| `RH_REGISTRY_USERNAME` | Red Hat Container Registry service account (not your AAP login) |
| `RH_REGISTRY_TOKEN` | From [access.redhat.com/terms-based-registry/accounts](https://access.redhat.com/terms-based-registry/accounts) |

Add registry flags to the recommended command above, or run:

```bash
./scripts/configure-aap-workshop-env.sh \
  --url https://sandbox-aap-rh-ee-mvandepe-dev.apps.rm1.0a51.p1.openshiftapps.com \
  --username admin \
  --password 'your-password' \
  --rh-registry-username <your-rh-registry-sa> \
  --rh-registry-token <your-rh-registry-token> \
  --apply
```

### 1. Create a Red Hat registry service account

1. Open [Red Hat Container Registry accounts](https://access.redhat.com/terms-based-registry/accounts).
2. Create a service account (or use an existing one).
3. Copy the **username** and **token** into `RH_REGISTRY_USERNAME` and `RH_REGISTRY_TOKEN`.

> **Why:** Ansible dynamic plugins are distributed as OCI artifacts on `registry.redhat.io`. The `install-dynamic-plugins` init container uses an `auth.json` secret created by `setup-developer-hub-aap.sh`. Without registry auth you will see:
>
> `unable to retrieve auth token: invalid username/password: unauthorized: Please login to the Red Hat Registry`

### 2. Ensure AAP Controller is running

For OpenShift sandbox AAP:

```bash
oc get ansibleautomationplatform sandbox-aap -n "$WORKSHOP_NAMESPACE"
oc get pods -n "$WORKSHOP_NAMESPACE" | grep sandbox-aap
oc get route sandbox-aap-controller -n "$WORKSHOP_NAMESPACE"
```

If pods are missing or routes return **503**, wait for the AAP operator to reconcile or check the `AnsibleAutomationPlatform` CR status:

```bash
oc get ansibleautomationplatform sandbox-aap -n "$WORKSHOP_NAMESPACE" -o jsonpath='{.status.URL}{"\n"}'
```

### 3. Create a Controller personal access token

**Manual (recommended):**

1. Open your Controller URL in a browser (gateway or controller route).
2. Sign in with your AAP admin or user account.
3. Go to **User → Tokens** (or **Access → Tokens** depending on AAP version).
4. Create a token with a descriptive name (e.g. `RHDH workshop`).
5. Copy the token value into `AAP_TOKEN` in `workshop.env`.

**Automatic (optional):**

If `AAP_TOKEN=changeme` but `AAP_ADMIN_USERNAME` and `AAP_ADMIN_PASSWORD` are set, `setup-developer-hub-aap.sh` attempts:

```http
POST {AAP_CONTROLLER_URL}/api/v2/tokens/
Authorization: Basic admin:password
{"description":"RHDH Ansible plugin (workshop)"}
```

On success, the script saves the new token to `scripts/workshop.env` via `upsert_workshop_env`.

### 4. Enable the plugin and apply configuration

```bash
source scripts/workshop.env
./scripts/setup-developer-hub-config.sh
```

Or run the Ansible-specific helper (registry secret, sidecar, rollout):

```bash
./scripts/setup-developer-hub-aap.sh
```

`setup-developer-hub-config.sh` when `AAP_ENABLED=true`:

1. Merges [`app-config-aap-snippet.yaml`](../../manifests/gitops/developer-hub/app-config-aap-snippet.yaml) into the live app-config ConfigMap
2. Appends [`dynamic-plugins-aap.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-aap.yaml) to the dynamic plugins ConfigMap
3. Calls `setup-developer-hub-aap.sh` (registry auth, dev-tools sidecar, pod restart)

### 5. Verify

**Plugin install logs:**

```bash
POD=$(oc get pod -n "$RHDH_NAMESPACE" -l app.kubernetes.io/name=developer-hub -o jsonpath='{.items[0].metadata.name}')
oc logs "$POD" -n "$RHDH_NAMESPACE" -c install-dynamic-plugins | grep -i ansible
```

Success looks like:

```text
=> Successfully installed dynamic plugin oci:registry.redhat.io/.../ansible-plugin-backstage-rhaap...
```

**Developer Hub UI:**

1. Sign in as `devhub` / `r#dh@t`.
2. Open **Ansible** in the sidebar or navigate to `/ansible`.
3. Confirm Controller content loads (jobs, templates, or connection status).

**App-config contains ansible block:**

```bash
oc get configmap redhat-developer-hub-app-config -n "$RHDH_NAMESPACE" \
  -o jsonpath='{.data.app-config\.yaml}' | grep -A5 '^ansible:'
```

---

## Scripts and manifests

### Scripts

| Script | Purpose |
|--------|---------|
| [`configure-aap-workshop-env.sh`](../../scripts/configure-aap-workshop-env.sh) | **Start here** — populate `workshop.env` from cluster routes, admin secret, and Controller API |
| [`setup-developer-hub-config.sh`](../../scripts/setup-developer-hub-config.sh) | Main entry — merges AAP plugins and app-config when `AAP_ENABLED=true`; calls AAP setup |
| [`setup-developer-hub-aap.sh`](../../scripts/setup-developer-hub-aap.sh) | Registry pull secret, dev-tools sidecar, rollout |

`setup-developer-hub-aap.sh` options:

| Option | Purpose |
|--------|---------|
| *(none)* | Apply secrets/patches and restart Developer Hub |
| `--no-rollout` | Apply only; no pod restart |
| `--force-rollout` | Restart even with `--no-rollout` |

### Manifests

| File | Purpose |
|------|---------|
| [`dynamic-plugins-aap.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-aap.yaml) | OCI plugins: frontend `/ansible` + scaffolder backend module |
| [`app-config-aap-snippet.yaml`](../../manifests/gitops/developer-hub/app-config-aap-snippet.yaml) | `ansible.rhaap`, `ansible.creatorService`, Ansible template catalog location |

### Cluster objects created at runtime

| Object | Purpose |
|--------|---------|
| Secret `redhat-developer-hub-dynamic-plugins-registry-auth` | `auth.json` mounted at `/opt/app-root/src/.config/containers` for OCI pulls |
| Secret `redhat-developer-hub-pull-secret` | Optional docker-registry secret for dev-tools image pull |
| Container `ansible-devtools-server` | Sidecar running `adt server` on port 8000 |
| ConfigMap `redhat-developer-hub-dynamic-plugins` | Updated with Ansible plugin entries |
| ConfigMap `redhat-developer-hub-app-config` | Updated with `ansible:` configuration block |

### Dynamic plugins installed

| OCI package | Plugin |
|-------------|--------|
| `oci://registry.redhat.io/ansible-automation-platform/automation-portal:2.1!ansible-plugin-backstage-rhaap` | Frontend — Ansible page, logo, `/ansible` route |
| `oci://registry.redhat.io/ansible-automation-platform/automation-portal:2.1!ansible-plugin-scaffolder-backend-module-backstage-rhaap` | Backend scaffolder module |

---

## OpenShift sandbox AAP notes

Many Developer Sandbox namespaces include an `AnsibleAutomationPlatform` CR named `sandbox-aap`:

```bash
oc get ansibleautomationplatform -n "$WORKSHOP_NAMESPACE"
```

Typical routes in the workshop namespace:

| Route | Purpose |
|-------|---------|
| `sandbox-aap` | AAP gateway |
| `sandbox-aap-controller` | Automation Controller (use this for `AAP_CONTROLLER_URL`) |
| `sandbox-aap-eda` | Event-Driven Ansible |

Auto-detection order in scripts:

1. Explicit `AAP_CONTROLLER_URL` in `workshop.env`
2. Route `sandbox-aap-controller` in `WORKSHOP_NAMESPACE`
3. `AnsibleAutomationPlatform/sandbox-aap` status URL (gateway)

Admin credentials for sandbox AAP are often stored in secrets such as `sandbox-aap-admin-password`. Set `AAP_ADMIN_USERNAME` / `AAP_ADMIN_PASSWORD` in `workshop.env` if you rely on automatic PAT creation — but still prefer creating and storing `AAP_TOKEN` explicitly.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Developer Hub pod `Init:CrashLoopBackOff` | Missing `RH_REGISTRY_*` | Set registry service account credentials; re-run `./scripts/setup-developer-hub-aap.sh` |
| `install-dynamic-plugins`: `Please login to the Red Hat Registry` | Invalid or missing registry auth | Verify `RH_REGISTRY_USERNAME` / `RH_REGISTRY_TOKEN`; check secret `redhat-developer-hub-dynamic-plugins-registry-auth` |
| No **Ansible** sidebar entry | Plugins not installed | Check init container logs; confirm `AAP_ENABLED=true` and configmap includes AAP plugins |
| Ansible page loads but empty / errors | Wrong URL or token | Set `AAP_CONTROLLER_URL` to controller route; use PAT not admin password |
| **Projects / jobs not listed** on Ansible page | Missing **catalog sync plugin** (`ansible-backstage-plugin-catalog-backend-module-rhaap`) | OCI installs use `…!ansible-backstage-plugin-catalog-backend-module-rhaap`, not the legacy tarball name `ansible-plugin-backstage-rhaap-backend`. Re-run `./scripts/setup-developer-hub-config.sh` and verify the plugin directory contains `package.json` |
| **My Items** empty while All shows content | User ownership filter | Projects synced to catalog need `relations.ownedBy` matching your Dev Hub user, or browse **All** instead of **My Items** |
| Ansible Catalog tab empty (no components) | No `Component` entities tagged `ansible` | The `/ansible` page lists catalog **Components** with tag `ansible` (from scaffolder-created playbook/collection projects), not raw Controller projects. Create one via **Create** tab templates, or check **All** after `catalog.providers.rhaap` sync runs |
| SSL / certificate errors talking to Controller | Strict TLS check | Set `AAP_CHECK_SSL=false` |
| Software templates fail | Dev-tools sidecar missing | Set `AAP_CREATOR_SERVICE_ENABLED=true`; confirm container `ansible-devtools-server` in pod |
| `Could not create AAP token automatically` | Controller API unreachable or wrong password | Create PAT manually in UI; set `AAP_TOKEN` |
| Controller route returns **503** | AAP pods not ready | `oc get pods -n $WORKSHOP_NAMESPACE \| grep sandbox-aap`; wait for operator |
| Init container stuck on lock | Stale PVC lock | `./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock` |

**Inspect init container failure:**

```bash
oc logs -n "$RHDH_NAMESPACE" -l app.kubernetes.io/name=developer-hub -c install-dynamic-plugins --tail=50
```

**Temporarily disable AAP** (restore Developer Hub if plugin install blocks startup):

```bash
export AAP_ENABLED=false
./scripts/setup-developer-hub-config.sh
```

Fix registry credentials, then set `AAP_ENABLED=true` and re-run.

---

## Security notes

- Treat `AAP_TOKEN` like any other secret — do not commit it to Git.
- The workshop merges the token into the app-config ConfigMap (same pattern as GitHub PAT). For production, use External Secrets or mounted files.
- `AAP_CHECK_SSL=false` is appropriate for sandbox PoC clusters; enable strict checking in production.
- Registry tokens grant pull access to Red Hat images — rotate if exposed.

---

## Related documentation

- [Red Hat: Integrating AAP with Developer Hub](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/integrating_with_red_hat_developer_hub/index)
- [Red Hat: Use the dynamic plugins cache](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/configuring_red_hat_developer_hub/use-the-dynamic-plugins-cache_configuring-rhdh)
- [06 — Install Developer Hub](06-install-developer-hub.md)
- [02 — Configure the workshop](02-configuration.md)

## Next step

Return to [Developer Hub catalog and integrations](07-developer-hub-catalog.md) or continue the [complete tutorial](TUTORIAL.md).
