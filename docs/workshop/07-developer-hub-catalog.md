# 7. Catalog, template, and integrations

Developer Hub loads catalog data from a **workshop catalog server** in your namespace and from inline ConfigMap entities.

## Apply catalog configuration

```bash
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
```

This script:

1. Creates/updates ConfigMap `workshop-catalog-entities` (entities, OpenAPI file, Tech Radar JSON)
2. Deploys `workshop-catalog-server` (Python HTTP server on a Route)
3. Restarts Developer Hub to reload catalog locations

Catalog server URLs:

- `https://workshop-catalog-server-<namespace>.<router>/entities.yaml`
- `https://workshop-catalog-server-<namespace>.<router>/people-api.yaml`
- `https://workshop-catalog-server-<namespace>.<router>/tech-radar.json`

## Catalog location

Configured in `app-config-rhdh.yaml`:

```yaml
catalog:
  locations:
    - type: file
      target: /catalog/entities.yaml
    - type: url
      target: https://workshop-catalog-server-<namespace>.<router>/entities.yaml
```

## Entities (`manifests/gitops/catalog/`)

| File | Kind | Purpose |
|------|------|---------|
| `all.yaml` | Location | Imports entities and templates (Git-hosted catalog) |
| `entities/people-service.yaml` | System + Component | Registers the demo app |
| `entities/people-api.yaml` | API | People REST API (OpenAPI from live backend) |
| `entities/quarkus-workshop-guide.yaml` | Component | Quarkus TechDocs site |
| `entities/platform-architecture-records.yaml` | Component | ADR TechDocs site |
| `openapi/people-api.yaml` | — | Static OpenAPI reference served by catalog server |
| `tech-radar.json` | — | Technology Radar data |
| `templates/quarkus-react-postgres-template.yaml` | Template | Scaffolder template |

### Component annotations

| Annotation | Integration |
|------------|-------------|
| `github.com/project-slug` | GitHub Actions (**CI**), Issues, and Pull Requests tabs |
| `backstage.io/source-location` | GitHub host for Issues plugin (must be a `url:https://github.com/.../` link) |
| `argocd/app-name` | Argo CD plugin — CD tab |
| `backstage.io/kubernetes-id` | Kubernetes plugin — resources tab |
| `backstage.io/kubernetes-namespace` | Limits K8s view to your namespace |

### API catalog and OpenAPI

The **People REST API** (`people-rest-api`) is linked from the `people-service` component via `providesApis`.

| Annotation | Integration |
|------------|-------------|
| `github.com/project-slug` | GitHub Actions (**CI**), Issues, and Pull Requests tabs on the API entity page |
| `backstage.io/source-location` | GitHub host for Issues plugin (must be a `url:https://github.com/.../` link) |
| `backstage.io/source-location` | Links the API to `apps/people-service` in GitHub |

| Endpoint | Description |
|----------|-------------|
| Backend `/q/openapi` | Live Quarkus spec (used as catalog API definition) |
| Frontend `/openapi.yaml` | Same spec via nginx proxy |
| Catalog server `/people-api.yaml` | Static reference copy |

In Developer Hub: **Catalog → APIs** or `/catalog?filters[kind]=api`.

Component API tab: `/catalog/default/component/people-service/api`.

People REST API CI tab (GitHub Actions workflow runs): `/catalog/default/api/people-rest-api/ci`.

People Service GitHub tabs (require `github.com/project-slug` on the entity):

| Tab | URL |
|-----|-----|
| CI | `/catalog/default/component/people-service/ci` |
| Issues | `/catalog/default/component/people-service/issues` |
| Pull Requests | `/catalog/default/component/people-service/pull-requests` |

The same tabs are available on the **People REST API** entity (`/catalog/default/api/people-rest-api/...`).

### Technology Radar

Plugins enabled in `dynamic-plugins-rhdh.yaml`:

- `oci://ghcr.io/.../backstage-community-plugin-github-actions` — CI tab with workflow runs
- `oci://ghcr.io/.../backstage-community-plugin-github-issues` — Issues tab linked to the repository
- `oci://ghcr.io/.../roadiehq-backstage-plugin-github-pull-requests` — Pull Requests tab linked to the repository
- `backstage-community-plugin-tech-radar`
- `backstage-community-plugin-tech-radar-backend-dynamic`

Data source in `app-config-rhdh.yaml`:

```yaml
techRadar:
  url: https://workshop-catalog-server-<namespace>.<router>/tech-radar.json
```

Open **Tech Radar** in the sidebar or visit `/tech-radar`.

### TechDocs documentation sites

Two TechDocs sites are published from `manifests/gitops/techdocs/` and mounted into Developer Hub:

| Entity | Pages | Content |
|--------|-------|---------|
| `quarkus-workshop-guide` | 7 | Working with Quarkus (dev mode, REST, persistence, OpenShift, Developer Hub) |
| `platform-architecture-records` | 6 | Sample architecture decision records (ADR-001 … ADR-005) |

Catalog annotations (TechDocs sources are mounted at `/catalog/techdocs/` inside Developer Hub):

```yaml
metadata:
  annotations:
    backstage.io/techdocs-ref: dir:./techdocs/quarkus-guide
    # ADR site uses dir:./techdocs/adrs
```

Sources live under `manifests/gitops/techdocs/`. The script `./scripts/setup-developer-hub-techdocs.sh` mounts them at `/catalog/techdocs/` inside Developer Hub.

TechDocs builder settings in `app-config-rhdh.yaml`:

```yaml
techdocs:
  builder: 'local'
  generator:
    runIn: 'local'
  publisher:
    type: 'local'
```

Open the **Documentation** tab on each entity:

- `/catalog/default/component/quarkus-workshop-guide/docs`
- `/catalog/default/component/platform-architecture-records/docs`

After editing TechDocs sources:

```bash
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
```

### Learning Paths

Workshop learning paths are served from `manifests/gitops/developer-hub/learning-paths.json` and proxied through Developer Hub:

| Label | URL |
|-------|-----|
| Developing with Quarkus | https://developers.redhat.com/learn/quarkus |
| Developing OpenShift applications with Java and Quarkus | https://developers.redhat.com/learn/openshift/developing-openshift-applications-java-and-quarkus |

Open **Learning Paths** in the sidebar or visit `/learning-paths`.

### Orchestrator workflow

The **Create Person in People API** workflow (`create-person`) authenticates with Keycloak and POSTs to `/api/people`.

Enable plugins and deploy Orchestrator infrastructure:

```bash
./scripts/setup-orchestrator.sh
```

When OpenShift **Serverless Logic** is not installed, the script deploys a standalone **Data Index** service (`sonataflow-platform-data-index-service`) so the Orchestrator UI loads. For full workflow execution, a cluster admin installs the operators once:

```bash
./scripts/install-orchestrator-infra.sh
./scripts/setup-orchestrator.sh
```

| Location | URL |
|----------|-----|
| Orchestrator UI | `/orchestrator` |
| People Service Workflows tab | `/catalog/default/component/people-service/workflows` |

Workflow definition: `manifests/gitops/orchestrator/create-person-sonataflow.yaml`

## Software template

Navigate to **Create** → **Quarkus + React + PostgreSQL on OpenShift**.

The template:

1. Fetches `apps/people-service/` from this repo
2. Publishes to a new GitHub repository (requires `GITHUB_TOKEN`)
3. Registers `catalog-info.yaml` in Developer Hub

## GitHub Actions integration

Workflows:

| Workflow | File | Purpose |
|----------|------|---------|
| People Service CI | `.github/workflows/people-service-ci.yaml` | Maven + Vite build on PR/push |
| Build and Push Container Images | `.github/workflows/build-and-push.yaml` | Publish images to GHCR on `main` |

The **CI** tab on the **People REST API** entity (`people-rest-api`) reads workflow runs via the GitHub Actions plugin. The API entity must include:

```yaml
metadata:
  annotations:
    github.com/project-slug: <org>/<repo>
```

Set `GITHUB_TOKEN` in `scripts/workshop.env` (and `app-secrets-rhdh`) to a GitHub PAT with `repo` and `workflow` read scopes so Developer Hub can list workflow runs.

The CI tab also prompts for **Authorize GitHub** (separate from Keycloak sign-in). Register a GitHub OAuth App and set:

```bash
export AUTH_GITHUB_CLIENT_ID="..."
export AUTH_GITHUB_CLIENT_SECRET="..."
```

OAuth callback URL:

```text
https://redhat-developer-hub-<namespace>.<router>/api/auth/github/handler/frame
```

Then re-run `./scripts/setup-developer-hub-config.sh`, or use the helper script:

```bash
./scripts/create-github-oauth-app.sh --oauth-app
```

That opens GitHub, saves `AUTH_GITHUB_CLIENT_ID` / `AUTH_GITHUB_CLIENT_SECRET` to `scripts/workshop.env`, applies Developer Hub config, and prints the OAuth App settings URL (`https://github.com/settings/applications/<client_id>`).

Fully automated alternative (GitHub App manifest flow):

```bash
./scripts/create-github-oauth-app.sh
```

### Reusing an existing OAuth App

| Goal | Command |
|------|---------|
| Re-apply existing credentials to Developer Hub | `./scripts/setup-github-oauth.sh` |
| First-time setup or new credentials | `./scripts/create-github-oauth-app.sh --oauth-app` |

Notes:

- Scripts **never delete** OAuth Apps on GitHub.
- Re-running `create-github-oauth-app.sh --oauth-app` opens the registration form again; paste existing Client ID/secret to reuse, or register only if you want a new app.
- Re-running the default manifest flow and clicking **Create** adds a **second** GitHub App; the old one remains.
- Lost client secret? Generate a new one in GitHub app settings, update `workshop.env`, then `./scripts/setup-github-oauth.sh`.

OAuth App settings URL:

```text
https://github.com/settings/applications/<client_id>
```

## Argo CD integration

The **CD** tab shows sync status when:

1. Argo CD Application `people-service` exists
2. `argo-secrets` contains a valid token (`./scripts/setup-argocd-token.sh`)
3. Component annotation `argocd/app-name` matches the Application name

## Customize for your fork

1. `manifests/gitops/catalog/entities/people-service.yaml` — GitHub slug and links
2. `manifests/gitops/catalog/entities/people-api.yaml` — GitHub slug for API CI tab
3. `scripts/workshop.env` — git repo URL, namespace, `CLUSTER_ROUTER_BASE`, `GITHUB_TOKEN`
3. Re-run `./scripts/configure-developer-hub-catalog.sh` and `./scripts/setup-developer-hub-config.sh`

## Next step

[Validation and troubleshooting](08-validation.md)
