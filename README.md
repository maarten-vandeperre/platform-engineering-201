# Platform Engineering 201

This is a demo branch - just to showcase a pr

Workshop repository for **Red Hat Developer Hub on OpenShift** with a sample **Quarkus + PostgreSQL + React** CRUD application, GitOps deployment, OpenAPI catalog, Technology Radar, and a Backstage software template.

## Start here

- **[Complete tutorial](docs/workshop/TUTORIAL.md)** — clean sandbox → full workshop state (commands, rationale, config links)
- [Workshop guide index](docs/workshop/README.md) — module index and quick reference

## Quick deploy (empty namespace)

```bash
cp scripts/workshop.env.example scripts/workshop.env
# Set WORKSHOP_NAMESPACE and CLUSTER_ROUTER_BASE for your cluster

oc login --token=<token> --server=<api-url>
chmod +x scripts/*.sh scripts/lib/*.sh
./scripts/bootstrap-workshop.sh
```

Helm instead of operators:

```bash
export WORKSHOP_INSTALL_METHOD=helm
./scripts/bootstrap-workshop.sh
```

Validate:

```bash
./scripts/validate-workshop.sh
./e2e/run-e2e.sh
```

## Repair (workloads scaled down)

```bash
./scripts/ensure-workshop-platform.sh   # Keycloak, RHDH PostgreSQL, catalog server
./scripts/repair-people-app.sh
./scripts/repair-developer-hub.sh
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
./scripts/create-github-oauth-app.sh --oauth-app   # GitHub Actions CI tab
```

## Repository structure

```
apps/people-service/          # Quarkus + React CRUD demo
manifests/gitops/             # Operators, Argo CD, app, Developer Hub, catalog
manifests/helm/               # Helm values for Argo CD and RHDH
scripts/                      # Bootstrap, install, repair, validate
e2e/                          # Selenium + HTTP end-to-end tests
docs/workshop/                # Step-by-step workshop documentation
.github/workflows/            # GHCR build pipeline
```

## Default OpenShift namespace

`rh-ee-mvandepe-dev` — override in `scripts/workshop.env`.
