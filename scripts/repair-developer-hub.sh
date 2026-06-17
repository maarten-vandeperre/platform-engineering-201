#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Repairing Developer Hub platform in ${RHDH_NAMESPACE}..."

require_oc
ensure_workshop_platform
ensure_catalog_entities_configmap

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/developer-hub-dynamic-plugins.sh"

if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Restarting Developer Hub (clearing stale dynamic-plugins lock if present)..."
  safe_rollout_developer_hub redhat-developer-hub "$(rollout_timeout_for_config)"
fi

wait_for_rhdh_route_ready 900
print_rhdh_route_url
echo "Developer Hub platform repair complete."
