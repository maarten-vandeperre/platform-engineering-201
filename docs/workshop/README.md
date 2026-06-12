# Developer Hub on OpenShift — Workshop Guide

This workshop installs **Red Hat Developer Hub** on OpenShift, deploys a sample **Quarkus + PostgreSQL + React** application with GitOps, and connects catalog entities, Argo CD, GitHub Actions, and a software template.

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/people-service/` | Sample CRUD application (Java Quarkus backend, React frontend) |
| `manifests/gitops/` | GitOps manifests for operators, Argo CD, the app, Developer Hub, and catalog |
| `scripts/` | Bootstrap and helper scripts (configurable via `workshop.env`) |
| `docs/workshop/` | Step-by-step workshop documentation |

## Quick start

1. Copy and edit configuration:

```bash
cp scripts/workshop.env.example scripts/workshop.env
# Edit WORKSHOP_NAMESPACE, git repo URL, GitHub org, etc.
```

2. Log in to OpenShift and select your project:

```bash
oc login --token=<token> --server=<api-url>
oc project rh-ee-mvandepe-dev   # or your namespace from workshop.env
```

3. Run the full bootstrap:

```bash
chmod +x scripts/*.sh scripts/lib/*.sh
./scripts/bootstrap-workshop.sh
```

4. Validate:

```bash
./scripts/validate-workshop.sh
```

## Workshop modules

1. [Prerequisites](01-prerequisites.md)
2. [Configure the workshop](02-configuration.md)
3. [Install operators](03-install-operators.md) — or [Install with Helm (no operators)](03b-install-with-helm.md)
4. [Set up Keycloak](04b-setup-keycloak.md)
5. [Deploy the People Service](04-deploy-people-app.md)
6. [Install OpenShift GitOps / Argo CD](05-setup-argocd.md)
7. [Install Developer Hub](06-install-developer-hub.md)
8. [Catalog, template, and integrations](07-developer-hub-catalog.md)
9. [Validation and troubleshooting](08-validation.md)

## What you will see in Developer Hub

After completing the workshop:

- **Catalog → Component**: `people-service` with links to GitHub, Keycloak, People UI/API, and OpenShift Topology
- **CD tab**: Argo CD sync status for the `people-service` application
- **CI/CD tab**: GitHub Actions workflow runs (requires a GitHub token)
- **Kubernetes / Topology tab**: Deployments, Services, Routes for `app.kubernetes.io/part-of=people-service`
- **Create → Template**: `Quarkus + React + PostgreSQL on OpenShift` scaffolder template

## Sample application

- **Frontend route**: `https://people-frontend-<namespace>.<cluster-domain>/`
- **Backend API**: `GET/POST/PUT/DELETE /api/people` (requires Keycloak token with `people-crud` role)
- **Keycloak**: admin `admin` / `r3dh@t`, People app user `user` / `r3dh@t`, Developer Hub user `devhub` / `r#dh@t` (also has People API access)
- **Health**: `GET /q/health` (unauthenticated)

Person object fields: `firstName`, `lastName`, `age`.

## GitHub Actions

Pushes to `main` under `apps/people-service/` trigger `.github/workflows/build-and-push.yaml`, which builds and pushes:

- `ghcr.io/<owner>/platform-engineering-201/people-backend:latest`
- `ghcr.io/<owner>/platform-engineering-201/people-frontend:latest`

To use GHCR images instead of OpenShift builds, set in `scripts/workshop.env`:

```bash
export WORKSHOP_BACKEND_IMAGE=ghcr.io/<owner>/platform-engineering-201/people-backend:latest
export WORKSHOP_FRONTEND_IMAGE=ghcr.io/<owner>/platform-engineering-201/people-frontend:latest
```

Ensure the namespace can pull from GHCR (image pull secret or public package).
