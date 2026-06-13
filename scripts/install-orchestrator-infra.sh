#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

require_oc
command -v helm >/dev/null 2>&1 || { echo "helm CLI is required" >&2; exit 1; }

RELEASE_NAME="${ORCHESTRATOR_INFRA_RELEASE:-orchestrator-infra}"
CHART_REPO="${ORCHESTRATOR_INFRA_REPO:-redhat-developer}"
CHART_NAME="${ORCHESTRATOR_INFRA_CHART:-redhat-developer-hub-orchestrator-infra}"
CHART_VERSION="${ORCHESTRATOR_INFRA_VERSION:-0.6.1}"

echo "Installing Orchestrator infrastructure (${CHART_NAME} ${CHART_VERSION})..."

helm repo add "${CHART_REPO}" https://redhat-developer.github.io/rhdh-chart >/dev/null 2>&1 || true
helm repo update "${CHART_REPO}" >/dev/null

if helm status "${RELEASE_NAME}" -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
  echo "Release ${RELEASE_NAME} already exists in ${WORKSHOP_NAMESPACE}."
else
  helm install "${RELEASE_NAME}" "${CHART_REPO}/${CHART_NAME}" \
    --version "${CHART_VERSION}" \
    -n "${WORKSHOP_NAMESPACE}" \
    --create-namespace
fi

cat <<EOF

Cluster admin action required:
  1. Approve InstallPlans for OpenShift Serverless and Serverless Logic operators.
  2. Wait until sonataflows.sonataflow.org CRD is available:
       oc api-resources | grep sonataflows
  3. Re-run:
       ./scripts/setup-orchestrator.sh

Then enable SonataFlowPlatform via Helm (optional, replaces standalone data index):
  helm upgrade redhat-developer-hub <rhdh-chart> -n ${RHDH_NAMESPACE} \\
    --reuse-values \\
    --set orchestrator.enabled=true \\
    --set orchestrator.serverlessOperator.enabled=false \\
    --set orchestrator.serverlessLogicOperator.enabled=true

EOF
