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

ensure_catalog_entities_configmap

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

deployment_has_techdocs() {
  oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.initContainers[] | select(.name == "prepare-techdocs")' >/dev/null 2>&1
}

backstage_has_techdocs_mount() {
  oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.containers[]
       | select(.name == "backstage-backend")
       | .volumeMounts[]
       | select(.name == "techdocs-workspace" and .mountPath == "/catalog/techdocs" and (.readOnly // false) == false)' >/dev/null 2>&1
}

backstage_has_catalog_entities_mount() {
  oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.containers[]
       | select(.name == "backstage-backend")
       | .volumeMounts[]
       | select(.name == "catalog-entities" and .mountPath == "/catalog/entities.yaml")' >/dev/null 2>&1
}

wait_for_techdocs_workspace() {
  local pod i
  echo "Waiting for TechDocs workspace in Developer Hub pod..."
  for i in $(seq 1 30); do
    pod="$(oc get pod -n "${RHDH_NAMESPACE}" -l app.kubernetes.io/name=developer-hub \
      -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null \
      | awk '{print $1}')"
    if [[ -n "${pod}" ]] \
      && oc exec -n "${RHDH_NAMESPACE}" "${pod}" -c backstage-backend -- \
        test -f /catalog/techdocs/quarkus-guide/mkdocs.yml 2>/dev/null; then
      echo "TechDocs workspace is ready in ${pod}."
      return 0
    fi
    if (( i == 30 )); then
      echo "Note: TechDocs workspace not verified yet; files appear after prepare-techdocs init completes." >&2
      return 0
    fi
    sleep 10
  done
}

echo "Preparing TechDocs file sources for Developer Hub in ${RHDH_NAMESPACE}..."
build_flat_techdocs_configmap "quarkus-guide"
build_flat_techdocs_configmap "adrs"

if deployment_has_techdocs && backstage_has_techdocs_mount && backstage_has_catalog_entities_mount; then
  echo "TechDocs init container and volume mounts already configured."
  wait_for_techdocs_workspace
  exit 0
fi

echo "Patching Developer Hub deployment with TechDocs init container..."
render_manifest "${MANIFESTS_DIR}/developer-hub/rhdh-techdocs-deployment-patch.yaml" \
  | oc patch deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" --type=strategic --patch-file=/dev/stdin

echo "Rolling out Developer Hub to apply TechDocs volumes..."
if developer_hub_uses_plugins_pvc redhat-developer-hub \
  || oc get pvc dynamic-plugins-root -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
  safe_rollout_developer_hub redhat-developer-hub 900s
else
  oc rollout restart deployment/redhat-developer-hub -n "${RHDH_NAMESPACE}"
  wait_for_developer_hub_rollout redhat-developer-hub 600s
fi

wait_for_techdocs_workspace

echo "TechDocs volumes configured on Developer Hub deployment."
echo "Open Documentation tabs:"
echo "  /catalog/default/component/quarkus-workshop-guide/docs"
echo "  /catalog/default/component/platform-architecture-records/docs"
