# Platform Engineering 201

_This originated after my Platform Engineering 101 sessions, where I got the question "nice, but how do I get started with it?". Well, let me show you._
  
  
Workshop repository for **Red Hat Developer Hub on OpenShift** with a sample **Quarkus + PostgreSQL + React** CRUD application, GitOps deployment, OpenAPI catalog, Technology Radar, optional Developer Lightspeed (OpenAI chat assistant), optional Ansible Automation Platform plugin, and a Backstage software template.

**Backstage note:** RHDH is Red Hat’s distribution of Backstage. The catalog, plugins, scaffolder, and app-config patterns in this repo apply to **Community Backstage** as well. This workshop is tested on OpenShift (`oc`); on vanilla Kubernetes you can follow the same ideas with `kubectl` and your own ingress/Helm install — see [Developer Hub and Backstage](docs/workshop/TUTORIAL.md#developer-hub-and-backstage) in the tutorial.

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
## Cleanup after demo

Remove all workshop resources for a fresh start (safe if the demo was partial):

```bash
./scripts/cleanup-workshop.sh --dry-run
./scripts/cleanup-workshop.sh --yes
```

See [09-cleanup-after-demo.md](docs/workshop/09-cleanup-after-demo.md).

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
