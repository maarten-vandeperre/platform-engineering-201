#!/bin/sh
set -eu

WORKSHOP_NAMESPACE="${WORKSHOP_NAMESPACE:-}"
CLUSTER_ROUTER_BASE="${CLUSTER_ROUTER_BASE:-}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-workshop}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-people-service}"
OIDC_ENABLED="${OIDC_ENABLED:-true}"

contains_placeholder() {
  case "$1" in
    *'$'*|*'${'* ) return 0 ;;
    '' ) return 0 ;;
    * ) return 1 ;;
  esac
}

if contains_placeholder "${WORKSHOP_NAMESPACE}"; then
  WORKSHOP_NAMESPACE=""
fi

if contains_placeholder "${CLUSTER_ROUTER_BASE}"; then
  CLUSTER_ROUTER_BASE=""
fi

if contains_placeholder "${KEYCLOAK_REALM}"; then
  KEYCLOAK_REALM="workshop"
fi

if contains_placeholder "${KEYCLOAK_CLIENT_ID}"; then
  KEYCLOAK_CLIENT_ID="people-service"
fi

if [ -n "${WORKSHOP_NAMESPACE}" ] && [ -n "${CLUSTER_ROUTER_BASE}" ]; then
  KEYCLOAK_URL="https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}"
else
  KEYCLOAK_URL="http://localhost:8180"
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
