# OpenShift deployment

The People Service is deployed to OpenShift with GitOps manifests under `manifests/gitops/people-app/`.

## Components

| Resource | Name |
|----------|------|
| Deployment | `people-backend`, `people-frontend`, `people-postgres` |
| Route | `people-backend`, `people-frontend` |
| Secret | `people-postgres` |

## Deploy or repair

```bash
./scripts/deploy-people-app.sh
./scripts/repair-people-app.sh
```

## Build images on cluster

```bash
./scripts/build-images-openshift.sh
```

Images are stored in the namespace ImageStreams and referenced by the Deployments.

## Runtime configuration

The frontend receives Keycloak and API URLs through a generated `config.js` ConfigMap (`workshop-runtime-config.yaml`).

## Validation

```bash
./scripts/validate-workshop.sh
```

This checks backend readiness, Keycloak tokens, frontend config, and OpenAPI exposure.
