#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build (if needed), publish plugin archives to workshop-catalog-server, and
restart Developer Hub to load the custom AAP Management plugin.

Options:
  --rebuild         Force rebuild of plugin bundles
  --no-rollout      Upload plugins only; do not restart Developer Hub
  -h, --help        Show this help

Requires in scripts/workshop.env:
  AAP_MANAGEMENT_ENABLED=true
  AAP_CONTROLLER_URL, AAP_TOKEN (or admin credentials)
  WORKSHOP_NAMESPACE / RHDH_NAMESPACE

See custom-plugins/aap-management/README.md
EOF
}

REBUILD=false
NO_ROLLOUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true ;;
    --no-rollout) NO_ROLLOUT=true ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

is_aap_management_enabled() {
  [[ "${AAP_MANAGEMENT_ENABLED:-false}" == "true" \
    || "${AAP_MANAGEMENT_ENABLED:-false}" == "1" \
    || "${AAP_MANAGEMENT_ENABLED:-false}" == "yes" ]]
}

if ! is_aap_management_enabled; then
  echo "AAP_MANAGEMENT_ENABLED is not true; skipping custom AAP Management plugin setup."
  exit 0
fi

require_oc

BUILD_DIR="${SCRIPTS_DIR}/../custom-plugins/aap-management/.build"
if [[ "${REBUILD}" == "true" || ! -f "${BUILD_DIR}/integrity.env" ]]; then
  "${SCRIPTS_DIR}/build-custom-aap-management-plugin.sh"
fi

# shellcheck disable=SC1091
source "${BUILD_DIR}/integrity.env"

render_manifest "${MANIFESTS_DIR}/developer-hub/aap-management-plugin-server.yaml" | oc apply -f -
oc rollout status deployment/aap-management-plugin-server -n "${WORKSHOP_NAMESPACE}" --timeout=300s

POD="$(oc get pod -n "${WORKSHOP_NAMESPACE}" -l app=aap-management-plugin-server \
  -o jsonpath='{.items[0].metadata.name}')"
oc exec -n "${WORKSHOP_NAMESPACE}" "${POD}" -- sh -c 'rm -rf /plugins/*'
oc cp "${BUILD_DIR}/aap-plugins/." "${WORKSHOP_NAMESPACE}/${POD}:/plugins" -c http

echo "Published plugin archives to aap-management-plugin-server:/plugins"

if [[ "${NO_ROLLOUT}" == "true" ]]; then
  echo "Plugin upload complete (Developer Hub rollout skipped)."
  exit 0
fi

echo "Applying Developer Hub config for AAP Management plugin..."
AAP_MANAGEMENT_ENABLED=true "${SCRIPTS_DIR}/setup-developer-hub-config.sh" 2>&1 | tail -5

RHDH_HOST="$(get_route_host "${RHDH_NAMESPACE}" redhat-developer-hub 2>/dev/null || true)"
echo "Custom AAP Management plugin setup complete."
if [[ -n "${RHDH_HOST}" ]]; then
  echo "Open https://${RHDH_HOST}/aap-management after signing in."
fi
