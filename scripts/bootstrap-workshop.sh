#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Platform Engineering 201 workshop bootstrap"
echo "Namespace: ${WORKSHOP_NAMESPACE}"
echo ""

chmod +x "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/lib/"*.sh 2>/dev/null || true

"${SCRIPT_DIR}/setup-keycloak.sh"
"${SCRIPT_DIR}/configure-keycloak-realm.sh"
"${SCRIPT_DIR}/deploy-people-app.sh"
"${SCRIPT_DIR}/setup-developer-hub-kubernetes.sh"
"${SCRIPT_DIR}/setup-developer-hub-config.sh"
"${SCRIPT_DIR}/configure-developer-hub-catalog.sh"
"${SCRIPT_DIR}/validate-workshop.sh"

echo ""
echo "Workshop bootstrap complete."
