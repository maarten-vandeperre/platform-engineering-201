# Getting started

The People Service backend lives in `apps/people-service/backend/`.

## Prerequisites

- Java 17+
- Maven 3.9+
- Optional: `oc` CLI and access to your OpenShift namespace

## Project layout

```
apps/people-service/backend/
├── pom.xml
├── src/main/java/.../entity/Person.java
├── src/main/java/.../resource/PersonResource.java
├── src/main/java/.../dto/
└── src/main/resources/
    ├── application.properties
    └── db/migration/V1__create_people.sql
```

## Build the application

```bash
cd apps/people-service/backend
./mvnw -DskipTests package
```

## Run locally

```bash
./mvnw quarkus:dev
```

Health endpoints:

- `http://localhost:8080/q/health`
- `http://localhost:8080/q/health/ready`

When OIDC is enabled locally, configure `application.properties` with your Keycloak realm URL before calling `/api/people`.

## Workshop deployment

On OpenShift the backend is exposed at:

```text
https://people-backend-<namespace>.<cluster-router>/api/people
```

Use `./scripts/validate-workshop.sh` to confirm database readiness and Keycloak integration.
