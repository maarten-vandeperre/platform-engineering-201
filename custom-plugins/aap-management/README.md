# Custom AAP Management plugin for Developer Hub

Workshop-local dynamic plugin that connects Developer Hub to an external **Ansible Automation Platform Controller** and provides:

- **Templates** tab — paginated job templates with search (name/description) and label filter, plus **Launch**
- **Run history** tab — paginated job runs with status and outcome

Route: `/aap-management` (sidebar: **AAP Templates**)

## Architecture

```text
Browser → RHDH frontend plugin → /api/aap-management/* → backend plugin → AAP Controller API
                                                              (/api/controller/v2/)
```

Credentials are **not** stored in the plugin source. They are merged into Developer Hub `app-config` from `scripts/workshop.env`.

## Configure

Add to `scripts/workshop.env`:

```bash
export AAP_MANAGEMENT_ENABLED=true
export AAP_CONTROLLER_URL=https://aap-aap.apps.cluster-w7kvs-1.dynamic2.redhatworkshops.io
export AAP_ADMIN_USERNAME=admin
export AAP_ADMIN_PASSWORD='your-password'
export AAP_TOKEN='your-controller-pat'   # preferred over password
export AAP_CHECK_SSL=false
```

Use a Controller **personal access token** (`AAP_TOKEN`) in production instead of admin password.

## Build

```bash
./scripts/build-custom-aap-management-plugin.sh
```

Produces:

- `custom-plugins/aap-management/.build/aap-plugins/*.tgz`
- `custom-plugins/aap-management/.build/integrity.env` (SHA-512 for dynamic plugin install)

## Deploy

```bash
./scripts/setup-custom-aap-management-plugin.sh
```

Or enable `AAP_MANAGEMENT_ENABLED=true` and run the full Developer Hub config script:

```bash
./scripts/setup-developer-hub-config.sh
```

The setup script uploads plugin archives to `aap-management-plugin-server` and restarts Developer Hub.

## Develop

```bash
cd custom-plugins/aap-management
yarn install
yarn workspace @internal/plugin-aap-management-backend build
yarn workspace @internal/plugin-aap-management build
yarn workspace @internal/plugin-aap-management-backend export-dynamic
yarn workspace @internal/plugin-aap-management export-dynamic
```

Backend API (authenticated Developer Hub user):

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/aap-management/job-templates` | List templates (`page`, `page_size`, `search`, `labels`) |
| POST | `/api/aap-management/job-templates/:id/launch` | Launch a template |
| GET | `/api/aap-management/jobs` | Job run history (`page`, `page_size`, `search`) |

## Files

| Path | Purpose |
|------|---------|
| `plugins/aap-management/` | Frontend dynamic plugin |
| `plugins/aap-management-backend/` | Backend proxy + AAP client |
| `manifests/gitops/developer-hub/dynamic-plugins-aap-management.yaml` | Dynamic plugin registration |
| `manifests/gitops/developer-hub/app-config-aap-management-snippet.yaml` | Controller connection config |
