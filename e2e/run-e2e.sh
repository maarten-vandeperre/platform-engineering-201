#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_ROOT}/scripts/workshop.env" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/workshop.env"
fi

export WORKSHOP_NAMESPACE="${WORKSHOP_NAMESPACE:-rh-ee-mvandepe-dev}"
export CLUSTER_ROUTER_BASE="${CLUSTER_ROUTER_BASE:-apps.rm1.0a51.p1.openshiftapps.com}"
export RHDH_URL="${RHDH_URL:-https://redhat-developer-hub-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}"
export RHDH_KEYCLOAK_USER="${RHDH_KEYCLOAK_USER:-devhub}"
export RHDH_KEYCLOAK_PASSWORD="${RHDH_KEYCLOAK_PASSWORD:-r#dh@t}"
export PEOPLE_KEYCLOAK_USER="${PEOPLE_KEYCLOAK_USER:-user}"
export PEOPLE_KEYCLOAK_PASSWORD="${PEOPLE_KEYCLOAK_PASSWORD:-r3dh@t}"
export PEOPLE_BACKEND_URL="${PEOPLE_BACKEND_URL:-https://people-backend-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}"
export PEOPLE_FRONTEND_URL="${PEOPLE_FRONTEND_URL:-https://people-frontend-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}"
export KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak-${WORKSHOP_NAMESPACE}.${CLUSTER_ROUTER_BASE}}"
export E2E_HEADLESS="${E2E_HEADLESS:-true}"
export E2E_TIMEOUT_SECONDS="${E2E_TIMEOUT_SECONDS:-180}"

if command -v oc >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/lib/common.sh"
  ensure_workshop_platform
fi

python3 -m pip install -q -r "${SCRIPT_DIR}/requirements.txt"
python3 -m pytest "${SCRIPT_DIR}/tests" -m e2e "$@"
