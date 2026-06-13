#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc

if ! oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  echo "Developer Hub deployment not found; skipping TechDocs volume setup."
  exit 0
fi

build_flat_techdocs_configmap() {
  local site="$1"
  local src="${MANIFESTS_DIR}/techdocs/${site}"
  local cm_name="rhdh-techdocs-${site}"
  local args=()
  local file base

  args+=(--from-file="catalog-info.yaml=${src}/catalog-info.yaml")
  args+=(--from-file="mkdocs.yml=${src}/mkdocs.yml")
  while IFS= read -r -d '' file; do
    base=$(basename "${file}")
    args+=(--from-file="docs-${base}=${file}")
  done < <(find "${src}/docs" -type f -name '*.md' -print0)

  oc create configmap "${cm_name}" \
    -n "${RHDH_NAMESPACE}" \
    "${args[@]}" \
    --dry-run=client -o yaml \
    | oc apply -f -
}

echo "Preparing TechDocs file sources for Developer Hub in ${RHDH_NAMESPACE}..."
build_flat_techdocs_configmap "quarkus-guide"
build_flat_techdocs_configmap "adrs"

echo "Patching Developer Hub deployment with TechDocs init container..."
replicas="$(oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" -o jsonpath='{.spec.replicas}')"
if [[ -z "${replicas}" || "${replicas}" == "0" ]]; then
  replicas=1
fi

echo "Scaling Developer Hub to 0 to avoid quota overlap during rollout..."
oc scale deployment/redhat-developer-hub -n "${RHDH_NAMESPACE}" --replicas=0
oc rollout status deployment/redhat-developer-hub -n "${RHDH_NAMESPACE}" --timeout=300s || true

render_manifest "${MANIFESTS_DIR}/developer-hub/rhdh-techdocs-deployment-patch.yaml" \
  | oc patch deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" --type=strategic --patch-file=/dev/stdin

echo "Scaling Developer Hub back to ${replicas} replica(s)..."
oc scale deployment/redhat-developer-hub -n "${RHDH_NAMESPACE}" --replicas="${replicas}"
oc rollout status deployment/redhat-developer-hub -n "${RHDH_NAMESPACE}" --timeout=600s

echo "TechDocs volumes configured on Developer Hub deployment."
