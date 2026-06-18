#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/orchestrator.sh"

echo "Setting up Orchestrator for Developer Hub in ${WORKSHOP_NAMESPACE}..."

require_oc
ensure_workshop_platform
resolve_keycloak_urls

if [[ -z "${KEYCLOAK_HOST:-}" ]]; then
  KEYCLOAK_HOST=$(get_route_host "${WORKSHOP_NAMESPACE}" "keycloak" 2>/dev/null || true)
  export KEYCLOAK_HOST
fi

export PEOPLE_KEYCLOAK_USER="${PEOPLE_KEYCLOAK_USER:-user}"
export PEOPLE_KEYCLOAK_PASSWORD="${PEOPLE_KEYCLOAK_PASSWORD:-r3dh@t}"
export KEYCLOAK_SERVICE_USER="${KEYCLOAK_SERVICE_USER:-${PEOPLE_KEYCLOAK_USER}}"
export KEYCLOAK_SERVICE_PASSWORD="${KEYCLOAK_SERVICE_PASSWORD:-${PEOPLE_KEYCLOAK_PASSWORD}}"

echo "Applying workflow configuration..."
render_manifest "${MANIFESTS_DIR}/orchestrator/create-person-props-configmap.yaml" | oc apply -f -

SCHEMAS_CM="$(mktemp)"
cat >"${SCHEMAS_CM}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: create-person-workflow-schemas
  namespace: ${WORKSHOP_NAMESPACE}
  labels:
    app.kubernetes.io/part-of: developer-hub
data:
  create-person.input-schema.json: |
$(sed 's/^/    /' "${MANIFESTS_DIR}/orchestrator/schemas/create-person.input-schema.json")
  create-person.output-schema.json: |
$(sed 's/^/    /' "${MANIFESTS_DIR}/orchestrator/schemas/create-person.output-schema.json")
EOF
oc apply -f "${SCHEMAS_CM}"
rm -f "${SCHEMAS_CM}"

apply_workflow_configmaps() {
  DEFINITION_CM="$(mktemp)"
  cat >"${DEFINITION_CM}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: create-person-workflow-definition
  namespace: ${WORKSHOP_NAMESPACE}
  labels:
    app.kubernetes.io/part-of: developer-hub
    app.kubernetes.io/component: orchestrator
data:
  create-person.sw.yaml: |
$(sed 's/^/    /' "${MANIFESTS_DIR}/orchestrator/create-person.sw.yaml")
EOF
  oc apply -f "${DEFINITION_CM}"
  rm -f "${DEFINITION_CM}"

  oc create configmap create-person-workflow-register -n "${WORKSHOP_NAMESPACE}" \
    --from-file=register-workflow.sh="${REPO_ROOT}/apps/create-person-workflow/register-workflow.sh" \
    --dry-run=client -o yaml | oc apply -f -
}

verify_workflow_input_schema() {
  local service_url="${1:-http://localhost:8080/management/processes/create-person}"
  echo "Verifying create-person workflow inputSchema..."
  if ! oc get deployment create-person-workflow -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    echo "Skipping inputSchema check (standalone create-person-workflow not deployed)."
    return 0
  fi
  local i response
  for i in $(seq 1 30); do
    response="$(oc exec -n "${WORKSHOP_NAMESPACE}" deploy/create-person-workflow -- \
      curl -sf "${service_url}" 2>/dev/null || true)"
    if [[ -n "${response}" ]] && echo "${response}" | grep -q '"inputSchema"'; then
      echo "Workflow inputSchema is available."
      return 0
    fi
    if (( i == 30 )); then
      echo "ERROR: ${service_url} does not return inputSchema." >&2
      echo "Run: ./scripts/repair-orchestrator.sh" >&2
      return 1
    fi
    sleep 5
  done
}

deploy_standalone_workflow() {
  apply_workflow_configmaps
  render_manifest "${MANIFESTS_DIR}/orchestrator/create-person-workflow.yaml" | oc apply -f -

  echo "Building create-person workflow image on OpenShift..."
  oc start-build create-person-workflow -n "${WORKSHOP_NAMESPACE}" \
    --from-dir="${REPO_ROOT}/apps/create-person-workflow" --wait --follow

  oc rollout restart deployment/create-person-workflow -n "${WORKSHOP_NAMESPACE}"
  oc rollout status deployment/create-person-workflow -n "${WORKSHOP_NAMESPACE}" --timeout=300s

  verify_workflow_input_schema "http://localhost:8080/management/processes/create-person"

  oc delete job register-create-person-workflow -n "${WORKSHOP_NAMESPACE}" --ignore-not-found
  render_manifest "${MANIFESTS_DIR}/orchestrator/register-create-person-workflow-job.yaml" | oc apply -f -

  echo "Waiting for workflow registration job..."
  oc wait --for=condition=complete job/register-create-person-workflow -n "${WORKSHOP_NAMESPACE}" --timeout=300s
  echo "create-person workflow registered in Data Index."
}

if ! data_index_is_ready; then
  if has_sonataflow_crd; then
    enable_orchestrator_via_helm || deploy_standalone_data_index
  else
    cat <<'ORCH_WARN_EOF' >&2
OpenShift Serverless Logic is not installed on this cluster.

Deploying a standalone Data Index service so the Orchestrator UI can load.
Workflow execution requires the Serverless Logic operator. A cluster
administrator can install it once with:

  ./scripts/install-orchestrator-infra.sh

Then re-run:
  ./scripts/setup-orchestrator.sh
ORCH_WARN_EOF
    deploy_standalone_data_index
  fi
fi

if has_sonataflow_crd; then
  echo "Deploying create-person workflow (SonataFlow)..."
  render_manifest "${MANIFESTS_DIR}/orchestrator/create-person-sonataflow.yaml" | oc apply -f -
  echo "Waiting for create-person workflow pod..."
  for i in $(seq 1 60); do
    if oc get pods -n "${WORKSHOP_NAMESPACE}" -l sonataflow.org/workflow=create-person \
      -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q true; then
      echo "create-person workflow pod is ready."
      break
    fi
    if (( i == 60 )); then
      echo "Warning: timed out waiting for create-person workflow pod." >&2
      echo "Check: oc get sonataflow,pods -n ${WORKSHOP_NAMESPACE}" >&2
    fi
    sleep 10
  done
elif ! oc get deployment create-person-workflow -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  deploy_standalone_workflow
fi

if oc get deployment create-person-workflow -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  verify_workflow_input_schema "http://localhost:8080/management/processes/create-person"
fi

orchestrator_skip_config() {
  case "${ORCHESTRATOR_SKIP_CONFIG:-}" in
    true | TRUE | yes | YES | 1) return 0 ;;
  esac
  return 1
}

if orchestrator_skip_config; then
  echo "Skipping Developer Hub config re-apply (ORCHESTRATOR_SKIP_CONFIG is set)."
else
  echo "Enabling Orchestrator plugins in Developer Hub..."
  "${SCRIPTS_DIR}/setup-developer-hub-config.sh"
fi

RHDH_HOST="$(resolve_rhdh_host)"
echo ""
echo "Orchestrator setup complete."
echo "Developer Hub Orchestrator: https://${RHDH_HOST}/orchestrator"
echo "People Service Workflows tab: https://${RHDH_HOST}/catalog/default/component/people-service/workflows"
