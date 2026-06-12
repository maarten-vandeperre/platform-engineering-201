#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

echo "Installing OpenShift GitOps and Red Hat Developer Hub operators in ${WORKSHOP_NAMESPACE}..."

ensure_project

apply_rendered_dir "${MANIFESTS_DIR}/operators"

wait_for_csv "${WORKSHOP_NAMESPACE}" "openshift-gitops-operator" 900 || true
wait_for_csv "${WORKSHOP_NAMESPACE}" "rhdh-operator" 900 || true

echo "Operator subscriptions applied. Check progress with:"
echo "  oc get csv -n ${WORKSHOP_NAMESPACE}"
