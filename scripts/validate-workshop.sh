#!/usr/bin/env bash
# Re-exec with bash when invoked as `sh script.sh` (macOS /bin/sh is bash in POSIX mode).
if [[ -z "${BASH_VERSION:-}" ]] || { shopt -oq posix 2>/dev/null; }; then
  exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Validating People Service deployment in ${WORKSHOP_NAMESPACE}..."

require_oc
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

ensure_workshop_platform

BACKEND_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "people-backend")
FRONTEND_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "people-frontend")

if [[ -z "${KEYCLOAK_URL:-}" ]]; then
  if oc get route keycloak -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    KEYCLOAK_URL="https://$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")"
  fi
fi

echo "== Backend health (unauthenticated) =="
curl -sk "https://${BACKEND_HOST}/q/health" | jq .

echo "== Backend readiness (database) =="
READY=$(curl -sk "https://${BACKEND_HOST}/q/health/ready")
echo "${READY}" | jq .
if [[ "$(echo "${READY}" | jq -r '.status // empty')" != "UP" ]]; then
  echo "Backend is not ready. Run ./scripts/repair-people-app.sh" >&2
  exit 1
fi

echo "== PostgreSQL pod =="
oc get pods -n "${WORKSHOP_NAMESPACE}" -l app=people-postgres -o wide
POSTGRES_READY=$(oc get pods -n "${WORKSHOP_NAMESPACE}" -l app=people-postgres \
  -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo false)
if [[ "${POSTGRES_READY}" != "true" ]]; then
  echo "PostgreSQL pod is not ready. Run ./scripts/repair-people-app.sh" >&2
  exit 1
fi

if [[ "${OIDC_ENABLED}" == "true" && -n "${KEYCLOAK_URL:-}" ]]; then
  echo "== Keycloak token for workshop user =="
  TOKEN_RESPONSE=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "client_id=${KEYCLOAK_CLIENT_ID}" \
    -d 'username=user' \
    -d 'password=r3dh@t' \
    -d 'grant_type=password')
  echo "${TOKEN_RESPONSE}" | jq '{token_type, expires_in, scope}'
  ACCESS_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')

  if [[ -z "${ACCESS_TOKEN}" || "${ACCESS_TOKEN}" == "null" ]]; then
    echo "Failed to obtain access token from Keycloak" >&2
    exit 1
  fi

  echo "== Unauthenticated API call should fail =="
  curl -sk -o /dev/null -w "HTTP %{http_code}\n" "https://${BACKEND_HOST}/api/people"

  echo "== Create person (authenticated) =="
  CREATE=$(curl -sk -X POST "https://${BACKEND_HOST}/api/people" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"firstName":"Ada","lastName":"Lovelace","age":36}')
  echo "${CREATE}" | jq .
  PERSON_ID=$(echo "${CREATE}" | jq -r '.id')

  echo "== List people (authenticated) =="
  curl -sk -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://${BACKEND_HOST}/api/people" | jq .

  echo "== Delete person ${PERSON_ID} (authenticated) =="
  curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X DELETE \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://${BACKEND_HOST}/api/people/${PERSON_ID}"
else
  echo "== Create person (OIDC disabled) =="
  CREATE=$(curl -sk -X POST "https://${BACKEND_HOST}/api/people" \
    -H 'Content-Type: application/json' \
    -d '{"firstName":"Ada","lastName":"Lovelace","age":36}')
  echo "${CREATE}" | jq .
  PERSON_ID=$(echo "${CREATE}" | jq -r '.id')

  echo "== List people =="
  curl -sk "https://${BACKEND_HOST}/api/people" | jq .

  echo "== Delete person ${PERSON_ID} =="
  curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X DELETE "https://${BACKEND_HOST}/api/people/${PERSON_ID}"
fi

echo "== Frontend runtime config =="
CONFIG_JS=$(curl -sk "https://${FRONTEND_HOST}/config.js")
echo "${CONFIG_JS}"
if echo "${CONFIG_JS}" | grep -q '\${'; then
  echo "Frontend config.js contains unresolved placeholders. Run ./scripts/repair-people-app.sh" >&2
  exit 1
fi

echo "== Frontend homepage =="
curl -sk -o /dev/null -w "HTTP %{http_code}\n" "https://${FRONTEND_HOST}/"

echo "== OpenAPI spec (backend) =="
OPENAPI=$(curl -sk "https://${BACKEND_HOST}/q/openapi")
printf '%s\n' "${OPENAPI}" | sed -n '1,5p'
if [[ "${OPENAPI}" != *openapi* && "${OPENAPI}" != *OpenAPI* ]]; then
  echo "Backend OpenAPI endpoint is not serving a spec" >&2
  exit 1
fi

echo "== OpenAPI aliases (frontend) =="
for OPENAPI_PATH in /q/openapi /openapi.yaml; do
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" "https://${FRONTEND_HOST}${OPENAPI_PATH}")
  echo "${OPENAPI_PATH}: HTTP ${CODE}"
  if [[ "${CODE}" != "200" ]]; then
    echo "Frontend OpenAPI path ${OPENAPI_PATH} failed. Apply people-frontend-nginx ConfigMap." >&2
    exit 1
  fi
done

if oc get route workshop-catalog-server -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  CATALOG_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "workshop-catalog-server")
  echo "== Catalog server =="
  curl -sk -o /dev/null -w "entities.yaml: HTTP %{http_code}\n" "https://${CATALOG_HOST}/entities.yaml"
  curl -sk -o /dev/null -w "tech-radar.json: HTTP %{http_code}\n" "https://${CATALOG_HOST}/tech-radar.json"
fi

if oc get route redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub")
  echo "== Developer Hub catalog endpoints =="
  echo "APIs: https://${RHDH_HOST}/catalog?filters%5Bkind%5D=api"
  echo "Tech Radar: https://${RHDH_HOST}/tech-radar"
fi

if [[ -n "${KEYCLOAK_URL:-}" ]]; then
  echo "== Keycloak readiness =="
  curl -sk -o /dev/null -w "HTTP %{http_code}\n" "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"

  RHDH_HOST="${RHDH_HOST:-redhat-developer-hub-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}"
  AUTH_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/auth?client_id=${RHDH_KEYCLOAK_CLIENT_ID}&response_type=code&scope=openid&redirect_uri=https%3A%2F%2F${RHDH_HOST}%2Fapi%2Fauth%2Foidc%2Fhandler%2Fframe"
  echo "== Developer Hub OIDC client in Keycloak =="
  AUTH_HEAD=$(curl -sk "${AUTH_URL}")
  if [[ "${AUTH_HEAD}" == *client\ not\ found* ]] || [[ "${AUTH_HEAD}" == *Client\ not\ found* ]]; then
    echo "Keycloak client '${RHDH_KEYCLOAK_CLIENT_ID}' is missing. Run ./scripts/configure-keycloak-realm.sh" >&2
    exit 1
  fi
  if [[ "${AUTH_HEAD}" != *login-pf* && "${AUTH_HEAD}" != *username* && "${AUTH_HEAD}" != *Sign\ in* ]]; then
    echo "Unexpected Keycloak auth response for client '${RHDH_KEYCLOAK_CLIENT_ID}'" >&2
    exit 1
  fi
  echo "OIDC client ${RHDH_KEYCLOAK_CLIENT_ID} is registered"

  echo "== Keycloak token for Developer Hub user (${RHDH_KEYCLOAK_USER}) =="
  DEVHUB_TOKEN=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "client_id=${RHDH_KEYCLOAK_CLIENT_ID}" \
    -d "client_secret=${RHDH_OIDC_CLIENT_SECRET}" \
    -d "username=${RHDH_KEYCLOAK_USER}" \
    -d "password=${RHDH_KEYCLOAK_PASSWORD}" \
    -d 'grant_type=password')
  echo "${DEVHUB_TOKEN}" | jq '{token_type, expires_in}'
  if [[ "$(echo "${DEVHUB_TOKEN}" | jq -r '.access_token // empty')" == "" ]]; then
    echo "Failed to obtain Developer Hub user token from Keycloak" >&2
    exit 1
  fi

  if oc get route redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub")
    echo "== Developer Hub route (from oc get route) =="
    print_rhdh_route_url

    echo "== Developer Hub homepage =="
    wait_for_route_ready "${RHDH_HOST}" "Developer Hub" 120 "/"

    echo "== Developer Hub OIDC redirect to Keycloak =="
    OIDC_START_CODE=$(curl -sk -o /tmp/workshop-rhdh-oidc.body -w "%{http_code}" \
      "https://${RHDH_HOST}/api/auth/oidc/start?env=production" || echo "000")
    echo "HTTP ${OIDC_START_CODE}"
    if [[ "${OIDC_START_CODE}" == "302" || "${OIDC_START_CODE}" == "303" ]]; then
      echo "Developer Hub OIDC redirect is working"
    elif route_response_is_application_unavailable /tmp/workshop-rhdh-oidc.body "${OIDC_START_CODE}"; then
      echo "Developer Hub route returns OpenShift 'Application is not available'." >&2
      echo "Use the URL from: oc get route redhat-developer-hub -n ${RHDH_NAMESPACE}" >&2
      exit 1
    elif [[ "${OIDC_START_CODE}" == "000" ]]; then
      echo "Could not reach Developer Hub route from this shell (curl HTTP 000)." >&2
      exit 1
    else
      echo "Unexpected HTTP ${OIDC_START_CODE} from OIDC start (expected 302 or 303)." >&2
      exit 1
    fi
  fi
fi

echo ""
echo "OpenShift resources:"
oc get deploy,svc,route,pvc -n "${WORKSHOP_NAMESPACE}" -l app.kubernetes.io/part-of=people-service

echo ""
echo "Validation complete."
