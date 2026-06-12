# 8. Validation and troubleshooting

## Automated validation

```bash
./scripts/validate-workshop.sh
```

Expected output:

- Backend health JSON with `"status": "UP"`
- Keycloak token obtained for user `user`
- HTTP 401 on unauthenticated API call (when OIDC enabled)
- Created person JSON with `id`, `firstName`, `lastName`, `age`
- List of people including the created record
- HTTP 204 on delete
- HTTP 200 on frontend `/`
- Keycloak token for Developer Hub user `devhub`
- HTTP 302 on Developer Hub OIDC start (redirect to Keycloak)
- OpenShift resources labeled `app.kubernetes.io/part-of=people-service`

## Manual checks

### OpenShift resources

```bash
oc get all,route,pvc -n $WORKSHOP_NAMESPACE -l app.kubernetes.io/part-of=people-service
```

### API CRUD (with Keycloak)

```bash
source scripts/workshop.env
KEYCLOAK_HOST=$(oc get route keycloak -o jsonpath='{.spec.host}')
BACKEND=$(oc get route people-backend -o jsonpath='{.spec.host}')

TOKEN=$(curl -sk -X POST "https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "client_id=${KEYCLOAK_CLIENT_ID}" \
  -d 'username=user' \
  -d 'password=r3dh@t' \
  -d 'grant_type=password' | jq -r .access_token)

# Create
curl -sk -X POST "https://${BACKEND}/api/people" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Katherine","lastName":"Johnson","age":44}'

# Read
curl -sk -H "Authorization: Bearer ${TOKEN}" "https://${BACKEND}/api/people" | jq .

# Update
curl -sk -X PUT "https://${BACKEND}/api/people/1" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Katherine","lastName":"Johnson","age":45}'

# Delete
curl -sk -X DELETE -H "Authorization: Bearer ${TOKEN}" "https://${BACKEND}/api/people/1"
```

### Builds

```bash
oc get builds -n $WORKSHOP_NAMESPACE
oc logs -f build/people-backend-1 -n $WORKSHOP_NAMESPACE
```

### Developer Hub (Keycloak SSO)

```bash
source scripts/workshop.env
KEYCLOAK_HOST=$(oc get route keycloak -o jsonpath='{.spec.host}')
RHDH_HOST=$(oc get route redhat-developer-hub -o jsonpath='{.spec.host}')

# Token for devhub user
curl -sk -X POST "https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "client_id=${RHDH_KEYCLOAK_CLIENT_ID}" \
  -d "client_secret=${RHDH_KEYCLOAK_CLIENT_SECRET}" \
  -d "username=${RHDH_KEYCLOAK_USER}" \
  -d "password=${RHDH_KEYCLOAK_PASSWORD}" \
  -d 'grant_type=password' | jq '{token_type, expires_in}'

# Should redirect (302) to Keycloak login
curl -sk -o /dev/null -w "HTTP %{http_code}\n" \
  "https://${RHDH_HOST}/api/auth/oidc/start?env=production"
```

Open `https://${RHDH_HOST}` and sign in as **`devhub` / `r#dh@t`**.

## Common issues

| Symptom | Fix |
|---------|-----|
| Backend `CrashLoopBackOff` | Check DB connectivity: `oc logs deployment/people-backend`. Ensure postgres is ready. |
| Image pull error for GHCR | Use OpenShift builds (default) or add `imagePullSecrets` |
| Build fails on Quarkus | Check build logs; cluster builder uses Java 17 UBI image |
| Argo CD 403 in Developer Hub | Re-run `./scripts/setup-argocd-token.sh` |
| GitHub Actions tab empty | Set valid `GITHUB_TOKEN` in `app-secrets-rhdh` |
| Catalog entity missing | Verify git URL in app-config; check `catalog-info.yaml` syntax |
| API returns 401/403 | Obtain Keycloak token; user must have `people-crud` role |
| Keycloak login loop | Check frontend `KEYCLOAK_URL` env matches Keycloak route |
| PostgreSQL not ready | `oc describe pod -l app=people-postgres` — check PVC binding |

## Clean up

```bash
oc delete application people-service -n $WORKSHOP_NAMESPACE --ignore-not-found
oc delete argocd workshop-gitops -n $WORKSHOP_NAMESPACE --ignore-not-found
oc delete backstage developer-hub -n $WORKSHOP_NAMESPACE --ignore-not-found
oc delete deployment,svc,route,bc,is,pvc,secret -l app.kubernetes.io/part-of=people-service -n $WORKSHOP_NAMESPACE
```

To remove operators, delete Subscriptions and CSVs (may require admin).
