#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Deploying Developer Hub in ${RHDH_NAMESPACE}..."

ensure_project

apply_rendered_dir "${MANIFESTS_DIR}/developer-hub"

echo "Waiting for Developer Hub Backstage CR..."
for _ in $(seq 1 60); do
  if oc get backstage "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

echo "Waiting for Developer Hub route..."
for _ in $(seq 1 60); do
  if oc get route redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1 \
    || oc get route "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

RHDH_HOST=$(get_route_host "${RHDH_NAMESPACE}" "redhat-developer-hub" 2>/dev/null \
  || get_route_host "${RHDH_NAMESPACE}" "${RHDH_INSTANCE_NAME}" 2>/dev/null || true)
if [[ -n "${RHDH_HOST}" ]]; then
  echo "Developer Hub: https://${RHDH_HOST}"
else
  echo "Developer Hub route not ready yet. Check: oc get backstage,route -n ${RHDH_NAMESPACE}"
fi

"${SCRIPTS_DIR}/setup-developer-hub-dynamic-plugins-cache.sh" --no-rollout || true
