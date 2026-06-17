#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Repairing Developer Hub platform in ${RHDH_NAMESPACE}..."

require_oc
ensure_workshop_platform

if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  oc delete pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" --wait=false
  wait_for_developer_hub_rollout redhat-developer-hub
fi

wait_for_rhdh_route_ready 900
print_rhdh_route_url
echo "Developer Hub platform repair complete."
