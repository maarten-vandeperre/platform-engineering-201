# ADR-004: GitOps deployment

## Status

Accepted

## Context

The workshop teaches platform engineering practices including declarative deployment and continuous delivery visibility.

## Decision

Store manifests in `manifests/gitops/` and optionally sync them with **Argo CD**. Component annotations link Developer Hub to the Argo CD application.

## Consequences

- Changes flow through Git rather than manual `oc` edits in production scenarios.
- The CD tab in Developer Hub shows sync status when Argo CD is configured.
- Bootstrap scripts support operator-based or Helm-based platform installation.
