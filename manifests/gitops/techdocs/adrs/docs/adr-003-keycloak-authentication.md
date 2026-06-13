# ADR-003: Keycloak authentication

## Status

Accepted

## Context

The workshop demonstrates secure API access and single sign-on for both the People UI and Developer Hub.

## Decision

Deploy **Keycloak** in the workshop namespace with a `workshop` realm, clients for `people-service` and Developer Hub, and role-based access (`people-crud`).

## Consequences

- All `/api/people` calls require a valid Bearer token when OIDC is enabled.
- Repair scripts ensure Keycloak stays scaled to at least one replica after idle namespaces.
- Frontend login redirects through Keycloak using runtime `config.js` values.
