#!/bin/sh
set -eu

KEYCLOAK_URL="${KEYCLOAK_URL:-}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-workshop}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-people-service}"
OIDC_ENABLED="${OIDC_ENABLED:-true}"
WORKSHOP_NAMESPACE="${WORKSHOP_NAMESPACE:-}"
CLUSTER_ROUTER_BASE="${CLUSTER_ROUTER_BASE:-}"

if [ -z "${KEYCLOAK_URL}" ] || printf '%s' "${KEYCLOAK_URL}" | grep -q '\$'; then
  if [ -n "${WORKSHOP_NAMESPACE}" ] && [ -n "${CLUSTER_ROUTER_BASE}" ]; then
    KEYCLOAK_URL="https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
  else
    KEYCLOAK_URL="http://localhost:8180"
  fi
fi

if [ -z "${KEYCLOAK_REALM}" ] || printf '%s' "${KEYCLOAK_REALM}" | grep -q '\$'; then
  KEYCLOAK_REALM="workshop"
fi

case "${OIDC_ENABLED}" in
  false|False|FALSE|0) OIDC_ENABLED=false ;;
  *) OIDC_ENABLED=true ;;
esac

cat > /tmp/config.js <<EOF
window.__RUNTIME_CONFIG__ = {
  keycloakUrl: '${KEYCLOAK_URL}',
  keycloakRealm: '${KEYCLOAK_REALM}',
  keycloakClientId: '${KEYCLOAK_CLIENT_ID}',
  oidcEnabled: ${OIDC_ENABLED},
};
EOF

exec nginx -g 'daemon off;'
