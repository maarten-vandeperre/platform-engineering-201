# 7. Catalog, template, and integrations

Developer Hub loads catalog data from this Git repository.

## Catalog location

Configured in `app-config-rhdh.yaml`:

```yaml
catalog:
  locations:
    - type: url
      target: https://github.com/<org>/platform-engineering-201/blob/main/manifests/gitops/catalog/all.yaml
```

## Entities (`manifests/gitops/catalog/`)

| File | Kind | Purpose |
|------|------|---------|
| `all.yaml` | Location | Imports entities and templates |
| `entities/people-service.yaml` | System + Component | Registers the demo app in the catalog |
| `templates/quarkus-react-postgres-template.yaml` | Template | Scaffolder template to clone the app pattern |

### Component annotations

| Annotation | Integration |
|------------|-------------|
| `github.com/project-slug` | GitHub Actions plugin — CI/CD tab |
| `argocd/app-name` | Argo CD plugin — CD tab |
| `backstage.io/kubernetes-id` | Kubernetes plugin — resources tab |
| `backstage.io/kubernetes-namespace` | Limits K8s view to your namespace |

### API catalog and OpenAPI

The **People REST API** is registered as a catalog `API` entity (`people-rest-api`). Its definition is loaded from the live Quarkus endpoint:

- Backend: `https://people-backend-<namespace>.<router>/q/openapi`
- Frontend proxy: `https://people-frontend-<namespace>.<router>/openapi.yaml`

Refresh catalog data after changes:

```bash
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
```

In Developer Hub open **Catalog → APIs** or visit `/catalog?filters[kind]=api`.

### Technology Radar

Workshop technologies (Quarkus, React, PostgreSQL, OpenShift, Keycloak, Argo CD, Developer Hub) are published in `manifests/gitops/catalog/tech-radar.json` and served by the workshop catalog server. Enable the Tech Radar plugins in `dynamic-plugins-rhdh.yaml` and configure `techRadar.url` in `app-config-rhdh.yaml`.

After changing catalog files, push to Git and refresh the catalog in Developer Hub (**Catalog → Register existing component** or wait for refresh interval).

## Software template

Navigate to **Create** → **Quarkus + React + PostgreSQL on OpenShift**.

The template:

1. Fetches `apps/people-service/` from this repo
2. Publishes to a new GitHub repository (requires `GITHUB_TOKEN`)
3. Registers `catalog-info.yaml` in Developer Hub

## GitHub Actions integration

Workflow: `.github/workflows/build-and-push.yaml`

- Triggers on push to `main` under `apps/people-service/`
- Builds backend with Maven + Quarkus
- Builds frontend with Node + Docker
- Pushes to GitHub Container Registry

Ensure `GITHUB_TOKEN` in `app-secrets-rhdh` has permission to read workflow runs for your repository.

## Argo CD integration

The **CD** tab shows sync status when:

1. Argo CD Application `people-service` exists
2. `argo-secrets` contains a valid token
3. Component annotation `argocd/app-name` matches the Application name

## Customize for your fork

Update these files after forking:

1. `manifests/gitops/catalog/entities/people-service.yaml` — GitHub slug and links
2. `scripts/workshop.env` — git repo URL and namespace
3. Re-run `./scripts/setup-developer-hub-config.sh`
