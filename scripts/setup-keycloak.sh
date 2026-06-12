#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Deploying Keycloak to ${WORKSHOP_NAMESPACE}..."

ensure_project

for file in keycloak-secret.yaml keycloak-realm-configmap.yaml keycloak-deployment.yaml keycloak-service.yaml keycloak-route.yaml; do
  render_manifest "${MANIFESTS_DIR}/keycloak/${file}" | oc apply -f -
done

echo "Waiting for Keycloak deployment..."
oc rollout status deployment/keycloak -n "${WORKSHOP_NAMESPACE}" --timeout=600s

KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak")
export KEYCLOAK_URL="https://${KEYCLOAK_HOST}"
export OIDC_AUTH_SERVER_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}"

echo "Keycloak admin console: ${KEYCLOAK_URL}/admin"
echo "  Username: ${KEYCLOAK_ADMIN_USER}"
echo "  Password: ${KEYCLOAK_ADMIN_PASSWORD}"
echo "Workshop realm: ${KEYCLOAK_REALM}"
echo "  Application user: user / r3dh@t (role: people-crud)"
echo "OIDC issuer: ${OIDC_AUTH_SERVER_URL}"

# Persist discovered URLs for subsequent deploy steps in this shell session.
if [[ -f "${SCRIPTS_DIR}/workshop.env" ]]; then
  if grep -q '^export KEYCLOAK_URL=' "${SCRIPTS_DIR}/workshop.env"; then
    if sed --version >/dev/null 2>&1; then
      sed -i "s|^export KEYCLOAK_URL=.*|export KEYCLOAK_URL=\"${KEYCLOAK_URL}\"|" "${SCRIPTS_DIR}/workshop.env"
      sed -i "s|^export OIDC_AUTH_SERVER_URL=.*|export OIDC_AUTH_SERVER_URL=\"${OIDC_AUTH_SERVER_URL}\"|" "${SCRIPTS_DIR}/workshop.env"
    else
      sed -i '' "s|^export KEYCLOAK_URL=.*|export KEYCLOAK_URL=\"${KEYCLOAK_URL}\"|" "${SCRIPTS_DIR}/workshop.env"
      sed -i '' "s|^export OIDC_AUTH_SERVER_URL=.*|export OIDC_AUTH_SERVER_URL=\"${OIDC_AUTH_SERVER_URL}\"|" "${SCRIPTS_DIR}/workshop.env"
    fi
  else
    {
      echo ""
      echo "# Auto-populated by setup-keycloak.sh"
      echo "export KEYCLOAK_URL=\"${KEYCLOAK_URL}\""
      echo "export OIDC_AUTH_SERVER_URL=\"${OIDC_AUTH_SERVER_URL}\""
    } >> "${SCRIPTS_DIR}/workshop.env"
  fi
fi

echo "Applying workshop realm clients and users..."
"${SCRIPTS_DIR}/configure-keycloak-realm.sh"

echo "Keycloak is ready."
