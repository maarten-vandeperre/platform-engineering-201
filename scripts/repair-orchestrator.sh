#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Repairing Orchestrator create-person workflow in ${WORKSHOP_NAMESPACE}..."

require_oc
ensure_workshop_platform
resolve_keycloak_urls

export PEOPLE_KEYCLOAK_USER="${PEOPLE_KEYCLOAK_USER:-user}"
export PEOPLE_KEYCLOAK_PASSWORD="${PEOPLE_KEYCLOAK_PASSWORD:-r3dh@t}"
export KEYCLOAK_SERVICE_USER="${KEYCLOAK_SERVICE_USER:-${PEOPLE_KEYCLOAK_USER}}"
export KEYCLOAK_SERVICE_PASSWORD="${KEYCLOAK_SERVICE_PASSWORD:-${PEOPLE_KEYCLOAK_PASSWORD}}"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

if ! oc get deployment create-person-workflow -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  echo "Standalone create-person-workflow deployment not found; running full setup..."
  exec "${SCRIPT_DIR}/setup-orchestrator.sh"
fi

echo "Applying create-person-workflow deployment manifest..."
render_manifest "${MANIFESTS_DIR}/orchestrator/create-person-workflow.yaml" | oc apply -f -

echo "Rebuilding create-person-workflow image..."
oc start-build create-person-workflow -n "${WORKSHOP_NAMESPACE}" \
  --from-dir="${REPO_ROOT}/apps/create-person-workflow" --wait --follow

oc rollout restart deployment/create-person-workflow -n "${WORKSHOP_NAMESPACE}"
oc rollout status deployment/create-person-workflow -n "${WORKSHOP_NAMESPACE}" --timeout=300s

response="$(oc exec -n "${WORKSHOP_NAMESPACE}" deploy/create-person-workflow -- \
  curl -sf http://localhost:8080/management/processes/create-person)"
if ! echo "${response}" | grep -q '"inputSchema"'; then
  echo "ERROR: workflow still missing inputSchema after rebuild." >&2
  echo "${response}" >&2
  exit 1
fi

execute_response="$(oc exec -n "${WORKSHOP_NAMESPACE}" deploy/create-person-workflow -- \
  curl -sf -X POST http://localhost:8080/create-person \
  -H 'Content-Type: application/json' \
  -d '{"workflowdata":{"firstName":"test","lastName":"workflow","age":42},"initiatorEntity":"component:default/people-service","targetEntity":"component:default/people-service"}')"
if ! echo "${execute_response}" | grep -q '"state":"COMPLETED"'; then
  echo "ERROR: orchestrator-style execute payload failed." >&2
  echo "${execute_response}" >&2
  exit 1
fi

echo "Workflow inputSchema and execute payload verified."

oc create configmap create-person-workflow-register -n "${WORKSHOP_NAMESPACE}" \
  --from-file=register-workflow.sh="${REPO_ROOT}/apps/create-person-workflow/register-workflow.sh" \
  --dry-run=client -o yaml | oc apply -f -

oc delete job register-create-person-workflow -n "${WORKSHOP_NAMESPACE}" --ignore-not-found
render_manifest "${MANIFESTS_DIR}/orchestrator/register-create-person-workflow-job.yaml" | oc apply -f -
oc wait --for=condition=complete job/register-create-person-workflow -n "${WORKSHOP_NAMESPACE}" --timeout=300s

RHDH_HOST="$(resolve_rhdh_host)"
echo ""
echo "Orchestrator repair complete."
echo "Run workflow: https://${RHDH_HOST}/orchestrator/workflows/create-person/execute"
