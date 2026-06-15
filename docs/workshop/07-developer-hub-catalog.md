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
| Catalog server `/people-api.yaml` | OpenAPI definition ingested by the catalog (Swagger UI source) |
| Backend `/q/openapi` | Live Quarkus spec (raw YAML) |
| Frontend `/openapi.yaml` | Same live spec via nginx proxy |

In Developer Hub: **Catalog → APIs** or `/catalog?filters[kind]=api`.

**Swagger UI (interactive API explorer):** open the **Definition** tab on the People REST API entity:

`/catalog/default/api/people-rest-api/definition`

The People Service component also links to this page as **Swagger UI** (Overview links card). Use **Raw OpenAPI (YAML)** only when you need the plain document.

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
- `red-hat-developer-hub-backstage-plugin-lightspeed` (optional; when `LIGHTSPEED_ENABLED=true` — see [06-install-developer-hub](06-install-developer-hub.md#developer-lightspeed))

Data source in `app-config-rhdh.yaml`:

```yaml
techRadar:
  url: https://workshop-catalog-server-<namespace>.<router>/tech-radar.json
```

Open **Tech Radar** in the sidebar or visit `/tech-radar`.

### Entity relations graph

Developer Hub ships the Backstage **Catalog Graph** plugin. Workshop catalog entities in `manifests/gitops/catalog/entities/organization-model.yaml` define owners, systems, `dependsOn`, and API links so the graph has meaningful nodes.

Configuration in `app-config-rhdh.yaml` enables the relations card and full graph page:

```yaml
app:
  extensions:
    - entity-card:catalog-graph/relations:
        config:
          title: Relations
          height: 400
          maxDepth: 1
    - page:catalog-graph
```

| View | Where to open it |
|------|------------------|
| Relations card (components) | **Dependencies** tab — e.g. `/catalog/default/component/people-service/dependencies` |
| Relations card (APIs, systems, resources) | **Overview** tab on those entity kinds |
| Full interactive graph | `/catalog-graph` (also reachable via **View Graph** on the relations card) |

After changing graph settings:

```bash
./scripts/setup-developer-hub-config.sh
```

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

When OpenShift **Serverless Logic** is not installed, the script deploys a standalone **Data Index** service (`sonataflow-platform-data-index-service`) so the Orchestrator UI loads. Use the Red Hat `logic-data-index-postgresql-rhel8:1.36.0` image (default in `ORCHESTRATOR_DATA_INDEX_IMAGE`); older images (including `quay.io/kiegroup/kogito-data-index-postgresql:latest` and `1.35.0`) lack `ProcessInstance.executionSummary` and break the **All runs** tab.

For full workflow execution, a cluster admin installs the operators once:

```bash
./scripts/install-orchestrator-infra.sh
./scripts/setup-orchestrator.sh
```

Add the annotation (must be a **JSON array** string — double quotes around workflow IDs):

```yaml
metadata:
  annotations:
    orchestrator.io/workflows: '["create-person"]'
```

| Location | URL |
|----------|-----|
| Orchestrator UI | `/orchestrator` |
| All runs | `/orchestrator/instances` |
| People Service Workflows tab | `/catalog/default/component/people-service/workflows` |
| People REST API Workflows tab | `/catalog/default/api/people-rest-api/workflows` |

Workflow definition: `manifests/gitops/orchestrator/create-person.sw.yaml`

The run form reads `dataInputSchema` from the workflow YAML and resolves it via the workflow service `GET /management/processes/create-person` (`inputSchema` field). The standalone FastAPI runtime in `apps/create-person-workflow/app.py` serves that schema; SonataFlow mounts `create-person-workflow-schemas` via `spec.resources`.

If the Orchestrator execute page shows **Missing JSON Schema for input form**, the workflow pod is running an old image. Rebuild it with:

```bash
./scripts/repair-orchestrator.sh
```

| File | Purpose |
|------|---------|
| `manifests/gitops/orchestrator/schemas/create-person.input-schema.json` | Form fields (first name, last name, age) |
| `apps/create-person-workflow/schemas/` | Same schema bundled in the standalone workflow image |

## Software template

Navigate to **Create** → **Quarkus + React + PostgreSQL on OpenShift**.

The template:

1. Fetches `apps/people-service-scaffold/` from GitHub (`fetch:template` requires a GitHub tree URL — plain HTTP tarballs are not supported). That folder is separate from the deployed workshop app in `apps/people-service/` and contains templated `catalog-info.yaml` (component name, GitHub slug, and owner are filled from the form).
2. Publishes to a new GitHub repository (**requires a GitHub PAT** with `repo` scope — run `./scripts/setup-github-auth.sh`)
3. Registers `catalog-info.yaml` in Developer Hub (use the same **Component name** as the new repository slug so the entity is unique)

To refresh the scaffold skeleton after changing `apps/people-service/`, run `./scripts/sync-people-service-scaffold.sh`.

Example target repository: `github.com/maarten-vandeperre/test-scaffolding-repo` (public).

If **Fetch skeleton** fails with `401 Unauthorized`, the cluster still has `GITHUB_TOKEN=changeme` in app-config — re-run `./scripts/setup-developer-hub-config.sh` (the script omits invalid tokens so public repo reads work).

If **Fetch skeleton** fails with `FetchUrlReader does not implement readTree`, the template URL points at a tarball — re-run `./scripts/configure-developer-hub-catalog.sh`.

If **Publish to GitHub** fails with `No token available for host: github.com`, run `./scripts/setup-github-auth.sh` and paste a PAT with `repo` scope.

If **Publish to GitHub** fails with `401`, re-run `./scripts/setup-github-auth.sh` with a valid token.

If **Publish to GitHub** fails with `publish:github is not registered`, enable `backstage-plugin-scaffolder-backend-module-github-dynamic` in `dynamic-plugins-rhdh.yaml` and run `./scripts/setup-developer-hub-config.sh`.

If **Register in catalog** fails with `409 Conflict`, that GitHub location is already registered (typical when re-scaffolding into the same repository). Either use a **new repository name**, or remove the old location in Developer Hub (**Administration** → **Locations**, find `…/test-scaffolding/…/catalog-info.yaml` → **Delete**), then run the template again. The template sets `optional: true` on `catalog:register` so re-runs succeed once the catalog config is updated.

If the component does not appear after a successful run, check **Component owner** is `guests` (not a custom name like `guests-owner` — only groups defined in the workshop catalog exist).

If Developer Hub stays in `Init:0/1` with `install-dynamic-plugins` logging `Waiting for lock release`, clear a stale lock on the plugins PVC:

```bash
./scripts/setup-developer-hub-dynamic-plugins-cache.sh --clear-lock
```

See [Dynamic plugins cache](06-install-developer-hub.md#dynamic-plugins-cache-faster-restarts) for details.

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

Set `GITHUB_TOKEN` via `./scripts/setup-github-auth.sh` (PAT with `repo` and `workflow` scopes) so Developer Hub can list workflow runs and run scaffolder publish.

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
| Configure OAuth + PAT together | `./scripts/setup-github-auth.sh --open-pat-url` |
| Re-apply PAT only (scaffolder publish) | `./scripts/setup-github-auth.sh --pat-only` |
| Re-apply OAuth only (CI tab) | `./scripts/setup-github-auth.sh --oauth-only` |
| First-time OAuth App setup | `./scripts/create-github-oauth-app.sh --oauth-app` |

Notes:

- Scripts **never delete** OAuth Apps on GitHub.
- Re-running `create-github-oauth-app.sh --oauth-app` opens the registration form again; paste existing Client ID/secret to reuse, or register only if you want a new app.
- Re-running the default manifest flow and clicking **Create** adds a **second** GitHub App; the old one remains.
- Lost client secret? Generate a new one in GitHub app settings, update `workshop.env`, then `./scripts/setup-github-auth.sh --oauth-only`.

OAuth App settings URL:

```text
https://github.com/settings/applications/<client_id>
```

## Argo CD integration

The **CD** tab shows sync status when:

1. Argo CD Application `people-service` exists
2. `argo-secrets` contains a valid token (`./scripts/setup-argocd-token.sh`)
3. Component annotation `argocd/app-name` matches the Application name

Catalog entities live under `manifests/gitops/catalog/entities/`. The **organization model** (3 teams, 8 users, 2 platforms, 4 apps, PostgreSQL, Keycloak, Kafka) is documented in [organization-entity-diagram.md](../catalog/diagrams/organization-entity-diagram.md).

## Customize for your fork

1. `scripts/workshop.env` — `WORKSHOP_GIT_REPO`, `WORKSHOP_GITHUB_ORG`, `WORKSHOP_GITHUB_REPO`, `WORKSHOP_GIT_BRANCH`, namespace, `CLUSTER_ROUTER_BASE`, `GITHUB_TOKEN`
2. Optional: edit catalog content in `manifests/gitops/developer-hub/catalog-configmap.yaml` (titles, tags, links — GitHub URLs use `${WORKSHOP_GITHUB_*}` placeholders)
3. Re-run `./scripts/configure-developer-hub-catalog.sh` and `./scripts/setup-developer-hub-config.sh`

## Egyptian theme branding

Developer Hub uses an **Egyptian-inspired** look (gold, lapis, papyrus) configured through RHDH branding in `app-config`:

| Asset / setting | Location |
|-----------------|----------|
| Color palettes (light + dark) | `manifests/gitops/developer-hub/egyptian-theme.yaml` |
| Sidebar logos (SVG → base64 at deploy time) | `manifests/gitops/developer-hub/branding/` |
| App title | `RHDH_APP_TITLE` in `scripts/workshop.env` (default: **Nile Developer Hub**) |

The theme is merged into `app-config` when you run:

```bash
./scripts/setup-developer-hub-config.sh
```

To tweak colors, edit `egyptian-theme.yaml` (see [RHDH theme and branding](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.9/html/customizing_red_hat_developer_hub/customize-rhdh-theme-and-branding_customizing-rhdh)). Replace the SVG logos in `branding/` to change the sidebar icon and expanded logo.

Users can still switch **Light**, **Dark**, or **Auto** from **Settings → Appearance**; both modes use the Egyptian palette.

## Developer Hub notifications (People API)

When a person is created via `POST /api/people`, the Quarkus backend sends a **broadcast notification** to Developer Hub using the [external notifications API](https://backstage.io/docs/notifications/):

`POST /api/notifications/notifications` with `Authorization: Bearer <token>`.

| Piece | Location |
|-------|----------|
| Notification client | [`apps/people-service/backend/src/main/java/com/redhat/workshop/people/notification/`](../../apps/people-service/backend/src/main/java/com/redhat/workshop/people/notification/) |
| Trigger on create | [`PersonResource.java`](../../apps/people-service/backend/src/main/java/com/redhat/workshop/people/resource/PersonResource.java) |
| Backend env (URL, enabled) | [`manifests/gitops/people-app/workshop-runtime-config.yaml`](../../manifests/gitops/people-app/workshop-runtime-config.yaml) |
| Bearer token (Secret) | [`manifests/gitops/people-app/backend-notifications-secret.yaml`](../../manifests/gitops/people-app/backend-notifications-secret.yaml) |
| RHDH external access token | [`manifests/gitops/developer-hub/app-config-rhdh.yaml`](../../manifests/gitops/developer-hub/app-config-rhdh.yaml) → `backend.auth.externalAccess` (static token scoped to `notifications`) |
| Shared token default | `PEOPLE_NOTIFICATION_TOKEN` in [`scripts/workshop.env`](../../scripts/workshop.env) (defaults to `BACKEND_SECRET`) |

After changing notification settings or backend code:

```bash
./scripts/setup-developer-hub-config.sh   # refresh RHDH app-config + restart
./scripts/deploy-people-app.sh            # rebuild backend + apply Secret/ConfigMap
```

Create a person in the People UI or via the API, then open the **Notifications** bell in Developer Hub (requires the notifications + signals plugins in [`dynamic-plugins-rhdh.yaml`](../../manifests/gitops/developer-hub/dynamic-plugins-rhdh.yaml)).

## Next step

[Validation and troubleshooting](08-validation.md)
