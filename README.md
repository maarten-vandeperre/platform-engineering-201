# Platform Engineering 201

Workshop repository for **Red Hat Developer Hub on OpenShift** with a sample **Quarkus + PostgreSQL + React** CRUD application, GitOps deployment, GitHub Actions, and a Backstage software template.

## Start here

- [Workshop guide](docs/workshop/README.md)

## Quick deploy

```bash
cp scripts/workshop.env.example scripts/workshop.env
# edit WORKSHOP_NAMESPACE if needed
chmod +x scripts/*.sh scripts/lib/*.sh
./scripts/bootstrap-workshop.sh
```

If PostgreSQL or the backend become unavailable later:

```bash
./scripts/repair-people-app.sh
./e2e/run-e2e.sh
```

## Repository structure

```
apps/people-service/          # Quarkus + React CRUD demo
manifests/gitops/             # Operators, Argo CD, app, Developer Hub, catalog
scripts/                      # Configurable bootstrap scripts
e2e/                          # Selenium end-to-end tests (Developer Hub login + topology)
docs/workshop/                # Step-by-step workshop documentation
.github/workflows/            # GHCR build pipeline
```

## Default OpenShift namespace

`rh-ee-mvandepe-dev` — override in `scripts/workshop.env`.
