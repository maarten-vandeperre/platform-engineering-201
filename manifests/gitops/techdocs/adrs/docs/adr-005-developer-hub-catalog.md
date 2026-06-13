# ADR-005: Developer Hub catalog

## Status

Accepted

## Context

Teams need a single portal to discover the People application, API specification, documentation, CI status, and platform standards.

## Decision

Register entities in Developer Hub via a **workshop catalog server** and inline ConfigMap entities. Enable dynamic plugins for Kubernetes, Tech Radar, GitHub Actions, TechDocs, Learning Paths, and Orchestrator workflows.

## Consequences

- Catalog updates require `./scripts/configure-developer-hub-catalog.sh`.
- TechDocs, learning paths, and Tech Radar data are served from the catalog server route.
- OAuth and PAT credentials in `scripts/workshop.env` gate GitHub and CI integrations.
