# REST APIs

The People REST API exposes CRUD operations for `Person` records.

## Resource

`PersonResource` maps to `/api/people` and uses JSON DTOs:

| Field | Type | Required |
|-------|------|----------|
| firstName | string | yes |
| lastName | string | yes |
| age | integer | yes |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/people` | List all people |
| POST | `/api/people` | Create a person |
| GET | `/api/people/{id}` | Get by ID |
| PUT | `/api/people/{id}` | Update |
| DELETE | `/api/people/{id}` | Delete |

## OpenAPI

Quarkus generates the specification at `/q/openapi`. Developer Hub imports this live spec for the **People REST API** catalog entity.

## Authentication

When `OIDC_ENABLED=true`, all API calls require a Bearer token from Keycloak with the `people-crud` role.

Example token request:

```bash
curl -sk -X POST "${KEYCLOAK_URL}/realms/workshop/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=people-service' \
  -d 'username=user' \
  -d 'password=r3dh@t' \
  -d 'grant_type=password'
```

Use the returned `access_token` in the `Authorization` header for API calls.
