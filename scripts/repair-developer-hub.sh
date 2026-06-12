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
  for i in $(seq 1 60); do
    ready=$(oc get pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "${ready}" == "True" ]]; then
      echo "Developer Hub pod is ready."
      break
    fi
    if (( i == 60 )); then
      echo "Warning: timed out waiting for Developer Hub pod." >&2
    fi
    sleep 10
  done
fi

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null \
  || echo "")
if [[ -n "${RHDH_HOST}" ]]; then
  echo "Developer Hub: https://${RHDH_HOST}"
fi
echo "Developer Hub platform repair complete."
