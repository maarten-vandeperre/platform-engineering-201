#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aap.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Configure Ansible Automation Platform integration for Red Hat Developer Hub:
  - registry.redhat.io pull secret for OCI dynamic plugins
  - optional ansible-devtools-server sidecar (Ansible software templates)
  - auto-detect controller URL from sandbox-aap CR when unset
  - create a Controller personal access token when AAP_TOKEN=changeme

Options:
  --force-rollout   Restart Developer Hub after patching
  --no-rollout      Apply secrets/patches only
  -h, --help        Show this help

Requires in scripts/workshop.env (or run ./scripts/configure-aap-workshop-env.sh first):
  AAP_ENABLED=true
  AAP_CONTROLLER_URL, AAP_TOKEN (or AAP admin creds to mint a token)
  RH_REGISTRY_USERNAME + RH_REGISTRY_TOKEN (registry.redhat.io service account)

See docs/workshop/06c-ansible-automation-platform.md
EOF
}

FORCE_ROLLOUT=false
NO_ROLLOUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-rollout) FORCE_ROLLOUT=true ;;
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

is_aap_enabled() {
  [[ "${AAP_ENABLED:-false}" == "true" \
    || "${AAP_ENABLED:-false}" == "1" \
    || "${AAP_ENABLED:-false}" == "yes" ]]
}

if ! is_aap_enabled; then
  echo "AAP_ENABLED is not true; skipping Ansible plugin setup."
  exit 0
fi

require_oc

detect_aap_controller_url() {
  local url
  if url="$(aap_detect_controller_url "${AAP_CONTROLLER_URL:-}")"; then
    export AAP_CONTROLLER_URL="${url}"
    echo "Using AAP_CONTROLLER_URL=${AAP_CONTROLLER_URL}"
    return 0
  fi
  echo "Set AAP_CONTROLLER_URL in scripts/workshop.env or run ./scripts/configure-aap-workshop-env.sh" >&2
  return 1
}

ensure_aap_token() {
  if [[ -n "${AAP_TOKEN:-}" && "${AAP_TOKEN}" != "changeme" ]]; then
    export AAP_TOKEN
    return 0
  fi

  local user pass base token
  user="${AAP_ADMIN_USERNAME:-admin}"
  pass="${AAP_ADMIN_PASSWORD:-changeme}"
  base="${AAP_CONTROLLER_URL%/}"

  if [[ "${pass}" == "changeme" ]]; then
    if pass="$(aap_read_admin_password_from_cluster 2>/dev/null || true)" && [[ -n "${pass}" ]]; then
      echo "Read AAP admin password from secret sandbox-aap-admin-password"
    else
      echo "Set AAP_TOKEN or run ./scripts/configure-aap-workshop-env.sh" >&2
      return 1
    fi
  fi

  if ! aap_api_reachable "${base}" "${user}" "${pass}" >/dev/null; then
    echo "Controller API not reachable at ${base}; cannot create token." >&2
    return 1
  fi

  echo "Creating AAP personal access token via ${base}/api/v2/tokens/ ..."
  if token="$(aap_create_token "${base}" "${user}" "${pass}")"; then
    export AAP_TOKEN="${token}"
    upsert_workshop_env AAP_TOKEN "${AAP_TOKEN}"
    echo "Created AAP token and saved AAP_TOKEN to scripts/workshop.env"
    return 0
  fi

  echo "Could not create AAP token automatically. Run ./scripts/configure-aap-workshop-env.sh or create a PAT in the Controller UI." >&2
  return 1
}

ensure_registry_pull_secret() {
  local secret_name="redhat-developer-hub-dynamic-plugins-registry-auth"
  local user token auth_b64 auth_json tmp

  if [[ -n "${RH_REGISTRY_PULL_SECRET:-}" ]]; then
    oc get secret "${RH_REGISTRY_PULL_SECRET}" -n "${RHDH_NAMESPACE}" \
      -o jsonpath='{.data.\.dockerconfigjson}' \
      | base64 -d > /tmp/rhdh-dockerconfig.json
    python3 - <<'PY' /tmp/rhdh-dockerconfig.json > /tmp/rhdh-auth.json
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    docker = json.load(handle)
auths = docker.get("auths", {})
redhat = auths.get("registry.redhat.io") or auths.get("https://registry.redhat.io")
if not redhat:
    sys.exit("registry.redhat.io not found in pull secret")
print(json.dumps({"auths": {"registry.redhat.io": redhat}}, indent=2))
PY
    oc create secret generic "${secret_name}" -n "${RHDH_NAMESPACE}" \
      --from-file=auth.json=/tmp/rhdh-auth.json \
      --dry-run=client -o yaml | oc apply -f -
    rm -f /tmp/rhdh-dockerconfig.json /tmp/rhdh-auth.json
    echo "Applied ${secret_name} from ${RH_REGISTRY_PULL_SECRET}"
    return 0
  fi

  user="${RH_REGISTRY_USERNAME:-changeme}"
  token="${RH_REGISTRY_TOKEN:-changeme}"
  if [[ "${user}" == "changeme" || "${token}" == "changeme" ]]; then
    echo "WARNING: RH_REGISTRY_USERNAME/RH_REGISTRY_TOKEN not set."
    echo "OCI Ansible plugins require registry.redhat.io auth. Create a service account at"
    echo "https://access.redhat.com/terms-based-registry/accounts and set:"
    echo "  export RH_REGISTRY_USERNAME=<service-account-name>"
    echo "  export RH_REGISTRY_TOKEN=<token>"
    return 1
  fi

  auth_b64="$(printf '%s:%s' "${user}" "${token}" | base64 | tr -d '\n')"
  tmp="$(mktemp)"
  cat >"${tmp}" <<EOF
{
  "auths": {
    "registry.redhat.io": {
      "auth": "${auth_b64}"
    }
  }
}
EOF
  oc create secret generic "${secret_name}" -n "${RHDH_NAMESPACE}" \
    --from-file=auth.json="${tmp}" \
    --dry-run=client -o yaml | oc apply -f -
  rm -f "${tmp}"
  echo "Applied ${secret_name} for registry.redhat.io"
}

ensure_image_pull_secret_on_deployment() {
  local deploy_name="$1"
  local pull_secret="${RH_REGISTRY_PULL_SECRET_NAME:-redhat-developer-hub-pull-secret}"

  if [[ -z "${RH_REGISTRY_USERNAME:-}" || "${RH_REGISTRY_USERNAME}" == "changeme" ]]; then
    return 0
  fi
  if [[ -z "${RH_REGISTRY_TOKEN:-}" || "${RH_REGISTRY_TOKEN}" == "changeme" ]]; then
    return 0
  fi

  oc create secret docker-registry "${pull_secret}" -n "${RHDH_NAMESPACE}" \
    --docker-server=registry.redhat.io \
    --docker-username="${RH_REGISTRY_USERNAME}" \
    --docker-password="${RH_REGISTRY_TOKEN}" \
    --dry-run=client -o yaml | oc apply -f -

  oc patch deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" --type=json \
    -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/imagePullSecrets\",\"value\":[{\"name\":\"${pull_secret}\"}]}]" \
    2>/dev/null \
    || oc patch deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" --type=json \
      -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/imagePullSecrets/-\",\"value\":{\"name\":\"${pull_secret}\"}}]" \
      2>/dev/null || true
}

ensure_ansible_devtools_sidecar() {
  local deploy_name="$1"
  local image="${AAP_DEVTOOLS_IMAGE:-registry.redhat.io/ansible-automation-platform-25/ansible-dev-tools-rhel8:latest}"

  if [[ "${AAP_CREATOR_SERVICE_ENABLED:-true}" != "true" \
    && "${AAP_CREATOR_SERVICE_ENABLED:-true}" != "1" \
    && "${AAP_CREATOR_SERVICE_ENABLED:-true}" != "yes" ]]; then
    echo "AAP_CREATOR_SERVICE_ENABLED=false; skipping ansible-devtools-server sidecar."
    return 0
  fi

  if oc get deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" -o json \
    | jq -e '.spec.template.spec.containers[] | select(.name == "ansible-devtools-server")' >/dev/null; then
    echo "ansible-devtools-server sidecar already present."
    return 0
  fi

  oc patch deployment "${deploy_name}" -n "${RHDH_NAMESPACE}" --type=json -p="[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/-\",\"value\":{
      \"name\":\"ansible-devtools-server\",
      \"image\":\"${image}\",
      \"imagePullPolicy\":\"IfNotPresent\",
      \"command\":[\"adt\",\"server\"],
      \"ports\":[{\"containerPort\":8000}]
    }}
  ]"
  echo "Added ansible-devtools-server sidecar to ${deploy_name}"
}

resolve_deploy_name() {
  if oc get deployment redhat-developer-hub -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    echo "redhat-developer-hub"
  elif oc get deployment "${RHDH_INSTANCE_NAME}" -n "${RHDH_NAMESPACE}" >/dev/null 2>&1; then
    echo "${RHDH_INSTANCE_NAME}"
  else
    echo ""
  fi
}

export AAP_CHECK_SSL="${AAP_CHECK_SSL:-false}"
detect_aap_controller_url
ensure_aap_token || true
ensure_registry_pull_secret || true

deploy_name="$(resolve_deploy_name)"
if [[ -z "${deploy_name}" ]]; then
  echo "Developer Hub deployment not found; registry secret applied. Re-run after RHDH is installed."
  exit 0
fi

ensure_image_pull_secret_on_deployment "${deploy_name}"
ensure_ansible_devtools_sidecar "${deploy_name}"

if [[ "${NO_ROLLOUT}" == "true" && "${FORCE_ROLLOUT}" != "true" ]]; then
  echo "Skipping rollout (--no-rollout)."
  exit 0
fi

echo "Restarting Developer Hub to install Ansible dynamic plugins..."
oc delete pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" --wait=false
for i in $(seq 1 90); do
  ready="$(oc get pod -l app.kubernetes.io/name=developer-hub -n "${RHDH_NAMESPACE}" \
    -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  if [[ "${ready}" == "True" ]]; then
    echo "Developer Hub pod is ready."
    break
  fi
  if (( i == 90 )); then
    echo "Warning: timed out waiting for Developer Hub pod." >&2
  fi
  sleep 10
done

echo "Ansible Automation Platform plugin setup complete."
echo "Open https://$(resolve_rhdh_host)/ansible after signing in."
