# Developer Hub integration

The People Service is registered in Red Hat Developer Hub as catalog entities.

## Catalog entities

| Entity | Kind | Purpose |
|--------|------|---------|
| `people-service` | Component | Application with Kubernetes, CI, Issues, Pull Requests, and docs tabs |
| `people-rest-api` | API | OpenAPI spec, GitHub Actions CI, Issues, and Pull Requests tabs |

## Annotations

Key annotations on `people-service`:

- `backstage.io/kubernetes-label-selector` — Kubernetes/Topology tab
- `github.com/project-slug` — GitHub Actions, Issues, and Pull Requests tabs
- `argocd/app-name` — Argo CD CD tab

## TechDocs

This guide is published through TechDocs and linked from the **Documentation** tab on the `quarkus-workshop-guide` catalog entity.

## Related workshop docs

- `docs/workshop/07-developer-hub-catalog.md`
- `docs/workshop/08-validation.md`

Re-apply catalog configuration after changes:

```bash
./scripts/configure-developer-hub-catalog.sh
./scripts/setup-developer-hub-config.sh
```
