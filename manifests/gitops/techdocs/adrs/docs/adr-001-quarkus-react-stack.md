# ADR-001: Quarkus + React stack

## Status

Accepted

## Context

The workshop needs a full-stack CRUD example that is familiar to Java developers, quick to build, and easy to deploy on OpenShift.

## Decision

Use **Quarkus** for the REST API and **React (Vite)** for the UI.

- Quarkus provides fast startup, built-in health checks, OpenAPI, and OIDC extensions.
- React keeps the frontend approachable for teams that split backend/frontend ownership.

## Consequences

- Two container images (backend + frontend) must be built and deployed.
- OpenAPI is generated from Quarkus and proxied through the frontend nginx route.
- Teams can scaffold similar stacks from the Developer Hub software template.
