#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Ensuring Keycloak realm objects for Developer Hub in ${KEYCLOAK_REALM}..."

require_oc
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

if [[ -z "${KEYCLOAK_URL:-}" ]]; then
  KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
  export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
fi

wait_for_keycloak() {
  local attempts="${1:-60}"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if curl -sk -o /dev/null -w '%{http_code}' "${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" | grep -q '^200$'; then
      return 0
    fi
    echo "Waiting for Keycloak (${i}/${attempts})..."
    sleep 5
  done
  echo "Keycloak did not become ready at ${KEYCLOAK_URL}" >&2
  return 1
}

wait_for_keycloak

ADMIN_TOKEN=$(curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "client_id=admin-cli" \
  -d "username=${KEYCLOAK_ADMIN_USER}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
  -d 'grant_type=password' | jq -r '.access_token')

if [[ -z "${ADMIN_TOKEN}" || "${ADMIN_TOKEN}" == "null" ]]; then
  echo "Failed to obtain Keycloak admin token" >&2
  exit 1
fi

kc() {
  curl -sk -H "Authorization: Bearer ${ADMIN_TOKEN}" -H 'Content-Type: application/json' "$@"
}

ensure_realm_role() {
  local role="$1"
  local description="$2"
  if ! kc "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/roles/${role}" | jq -e '.name' >/dev/null 2>&1; then
    kc -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/roles" \
      -d "{\"name\":\"${role}\",\"description\":\"${description}\"}" >/dev/null
    echo "Created realm role ${role}"
  fi
}

ensure_realm_role "people-crud" "Create, read, update, and delete people records"
ensure_realm_role "developer-hub-user" "Sign in to Red Hat Developer Hub"

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null \
  || echo "redhat-developer-hub-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}")
RHDH_HOST="${RHDH_ROUTE_HOST:-${RHDH_HOST}}"
if [[ -z "${RHDH_HOST}" || "${RHDH_HOST}" == *".."* ]]; then
  echo "Unable to determine Developer Hub route host for Keycloak redirect URIs" >&2
  exit 1
fi
PEOPLE_FRONTEND_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "people-frontend" 2>/dev/null \
  || echo "people-frontend-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}")

RHDH_REDIRECT_URI="https://${RHDH_HOST}/api/auth/oidc/handler/frame"
RHDH_WEB_ORIGIN="https://${RHDH_HOST}"
PEOPLE_WEB_ORIGIN="https://${PEOPLE_FRONTEND_HOST}"

ensure_oidc_client() {
  local client_id="$1"
  local name="$2"
  local public_client="$3"
  local secret="${4:-}"
  shift 4
  local redirect_uris=("$@")

  local internal_id
  internal_id=$(kc "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${client_id}" | jq -r '.[0].id // empty')

  local uris_json
  uris_json=$(printf '%s\n' "${redirect_uris[@]}" | jq -R . | jq -s .)

  local payload
  if [[ "${public_client}" == "true" ]]; then
    payload=$(jq -n \
      --arg clientId "${client_id}" \
      --arg name "${name}" \
      --argjson redirectUris "${uris_json}" \
      '{
        clientId: $clientId,
        name: $name,
        enabled: true,
        publicClient: true,
        standardFlowEnabled: true,
        directAccessGrantsEnabled: true,
        protocol: "openid-connect",
        redirectUris: $redirectUris,
        webOrigins: ["+"],
        attributes: { "post.logout.redirect.uris": "+" }
      }')
  else
    payload=$(jq -n \
      --arg clientId "${client_id}" \
      --arg name "${name}" \
      --arg secret "${secret}" \
      --argjson redirectUris "${uris_json}" \
      '{
        clientId: $clientId,
        name: $name,
        enabled: true,
        publicClient: false,
        secret: $secret,
        standardFlowEnabled: true,
        directAccessGrantsEnabled: true,
        protocol: "openid-connect",
        redirectUris: $redirectUris,
        webOrigins: ["+"],
        attributes: { "post.logout.redirect.uris": "+" }
      }')
  fi

  if [[ -z "${internal_id}" ]]; then
    kc -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients" -d "${payload}" >/dev/null
    echo "Created OIDC client ${client_id}"
  else
    kc -X PUT "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${internal_id}" -d "${payload}" >/dev/null
    echo "Updated OIDC client ${client_id}"
  fi
}

ensure_oidc_client "${RHDH_KEYCLOAK_CLIENT_ID}" "Developer Hub" "false" "${RHDH_KEYCLOAK_CLIENT_SECRET}" \
  "${RHDH_REDIRECT_URI}" \
  "${RHDH_WEB_ORIGIN}/*" \
  "http://localhost:7007/api/auth/oidc/handler/frame"

ensure_oidc_client "${KEYCLOAK_CLIENT_ID}" "People Service" "true" \
  "${PEOPLE_WEB_ORIGIN}/*" \
  "${PEOPLE_WEB_ORIGIN}/" \
  "http://localhost:5173/*" \
  "http://localhost:8080/*"

ensure_user() {
  local username="$1"
  local password="$2"
  local email="$3"
  local first="$4"
  local last="$5"
  shift 5
  local roles=("$@")

  local user_id
  user_id=$(kc "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}" | jq -r '.[0].id // empty')
  if [[ -z "${user_id}" ]]; then
    kc -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users" -d "{
      \"username\": \"${username}\",
      \"enabled\": true,
      \"emailVerified\": true,
      \"firstName\": \"${first}\",
      \"lastName\": \"${last}\",
      \"email\": \"${email}\"
    }" >/dev/null
    user_id=$(kc "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users?username=${username}" | jq -r '.[0].id')
    echo "Created user ${username}"
  fi

  kc -X PUT "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/reset-password" \
    -d "{\"type\":\"password\",\"value\":\"${password}\",\"temporary\":false}" >/dev/null

  for role in "${roles[@]}"; do
    local role_json
    role_json=$(kc "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/roles/${role}")
    kc -X POST "${KEYCLOAK_URL}/admin/realms/${KEYCLOAK_REALM}/users/${user_id}/role-mappings/realm" \
      -d "[${role_json}]" >/dev/null 2>&1 || true
  done
}

ensure_user "user" "r3dh@t" "user@workshop.example" "Workshop" "User" "people-crud"
ensure_user "${RHDH_KEYCLOAK_USER}" "${RHDH_KEYCLOAK_PASSWORD}" "devhub@workshop.example" "Developer" "Hub" \
  "developer-hub-user" "people-crud"

echo "Keycloak realm configuration complete."
