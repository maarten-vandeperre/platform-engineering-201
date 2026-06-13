# ADR-002: PostgreSQL data store

## Status

Accepted

## Context

The People API persists person records and must survive pod restarts in the workshop namespace.

## Decision

Use **PostgreSQL** with Flyway migrations and a dedicated `people-postgres` Deployment plus PVC.

## Consequences

- Workshop scripts include repair logic for postgres crash-loops and optional data reset.
- Backend readiness checks include a database health probe visible in `/q/health/ready`.
- Production deployments would use managed database services instead of in-cluster postgres.
