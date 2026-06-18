#!/usr/bin/env bash
# Shared Orchestrator / Data Index helpers for bootstrap and setup-orchestrator.sh.
set -euo pipefail

orchestrator_enabled() {
  case "${SKIP_ORCHESTRATOR:-}" in
    true | TRUE | yes | YES | 1) return 1 ;;
  esac
  return 0
}

has_sonataflow_crd() {
  oc api-resources 2>/dev/null | awk '{print $1}' | grep -qx 'sonataflows'
}

data_index_is_ready() {
  if oc get svc sonataflow-platform-data-index-service -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1 \
    && oc get deployment sonataflow-platform-data-index -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    local ready
    ready=$(oc get deployment sonataflow-platform-data-index -n "${WORKSHOP_NAMESPACE}" \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "${ready:-0}" == "1" ]]; then
      return 0
    fi
  fi
  if oc get sonataflowplatform sonataflow-platform -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    local endpoint
    endpoint=$(oc get sonataflowplatform sonataflow-platform -n "${WORKSHOP_NAMESPACE}" \
      -o jsonpath='{.status.services.dataIndex.endpoint}' 2>/dev/null || true)
    if [[ -n "${endpoint}" ]]; then
      return 0
    fi
  fi
  return 1
}

wait_for_data_index() {
  echo "Waiting for sonataflow-platform-data-index-service..."
  local i ready endpoint
  for i in $(seq 1 60); do
    if data_index_is_ready; then
      if oc get deployment sonataflow-platform-data-index -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
        echo "Data Index service is ready."
      else
        endpoint=$(oc get sonataflowplatform sonataflow-platform -n "${WORKSHOP_NAMESPACE}" \
          -o jsonpath='{.status.services.dataIndex.endpoint}' 2>/dev/null || true)
        echo "SonataFlowPlatform Data Index is ready at ${endpoint}."
      fi
      return 0
    fi
    if (( i == 60 )); then
      echo "Warning: timed out waiting for Data Index service." >&2
      echo "Check: oc get deploy,svc,pods -n ${WORKSHOP_NAMESPACE} | grep -i sonata" >&2
      return 1
    fi
    sleep 10
  done
}

deploy_standalone_data_index() {
  export ORCHESTRATOR_DATA_INDEX_IMAGE="${ORCHESTRATOR_DATA_INDEX_IMAGE:-registry.redhat.io/openshift-serverless-1/logic-data-index-postgresql-rhel8:1.36.0}"
  echo "Deploying standalone Data Index service..."
  echo "Using image: ${ORCHESTRATOR_DATA_INDEX_IMAGE}"
  render_manifest "${MANIFESTS_DIR}/orchestrator/data-index.yaml" | oc apply -f -
  oc wait --for=condition=complete job/sonataflow-create-db -n "${WORKSHOP_NAMESPACE}" --timeout=300s \
    || echo "Warning: sonataflow database job did not complete in time." >&2
  wait_for_data_index || true
}

enable_orchestrator_via_helm() {
  if ! command -v helm >/dev/null 2>&1; then
    return 1
  fi
  if ! helm status redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    return 1
  fi

  echo "Enabling Orchestrator SonataFlowPlatform via Helm..."
  helm upgrade redhat-developer-hub "${RHDH_HELM_CHART:-https://github.com/openshift-helm-charts/charts/releases/download/redhat-redhat-developer-hub-1.9.3/redhat-developer-hub-1.9.3.tgz}" \
    -n "${RHDH_NAMESPACE}" \
    --reuse-values \
    --set orchestrator.enabled=true \
    --set orchestrator.serverlessOperator.enabled=false \
    --set orchestrator.serverlessLogicOperator.enabled=true \
    --wait --timeout 15m
}

try_install_orchestrator_infra() {
  if ! command -v helm >/dev/null 2>&1; then
    echo "Note: helm not available; skipping orchestrator-infra install."
    return 0
  fi
  echo "Attempting Orchestrator infrastructure install (operators may require cluster-admin approval)..."
  "${SCRIPTS_DIR}/install-orchestrator-infra.sh" \
    || echo "Note: Orchestrator infra install skipped or failed; standalone Data Index will be used."
}

# Deploy and wait for Data Index before RHDH enables the orchestrator plugin.
ensure_orchestrator_data_index() {
  require_oc

  if data_index_is_ready; then
    echo "Orchestrator Data Index is already ready in ${WORKSHOP_NAMESPACE}."
    return 0
  fi

  echo "Ensuring Orchestrator Data Index is available in ${WORKSHOP_NAMESPACE}..."

  if has_sonataflow_crd; then
    enable_orchestrator_via_helm || deploy_standalone_data_index
  else
    try_install_orchestrator_infra
    if has_sonataflow_crd; then
      enable_orchestrator_via_helm || deploy_standalone_data_index
    else
      deploy_standalone_data_index
    fi
  fi

  wait_for_data_index || echo "Warning: Data Index may not be ready yet." >&2
}
