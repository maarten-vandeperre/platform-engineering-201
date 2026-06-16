#!/usr/bin/env bash
# Shared helpers for Ansible Automation Platform workshop integration.
# shellcheck disable=SC2034

aap_normalize_url() {
  local url="${1:-}"
  url="${url%/}"
  if [[ -z "${url}" ]]; then
    return 1
  fi
  if [[ "${url}" != http://* && "${url}" != https://* ]]; then
    url="https://${url}"
  fi
  printf '%s' "${url}"
}

aap_route_host() {
  local route_name="$1"
  oc get route "${route_name}" -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.spec.host}' 2>/dev/null || true
}

aap_detect_controller_url() {
  local hint_url="${1:-${AAP_CONTROLLER_URL:-}}"

  if [[ -n "${hint_url}" && "${hint_url}" != "changeme" ]]; then
    printf '%s' "$(aap_normalize_url "${hint_url}")"
    return 0
  fi

  local controller_host gateway_host cr_url
  controller_host="$(aap_route_host sandbox-aap-controller)"
  if [[ -n "${controller_host}" ]]; then
    printf 'https://%s' "${controller_host}"
    return 0
  fi

  gateway_host="$(aap_route_host sandbox-aap)"
  if [[ -n "${gateway_host}" ]]; then
    # Prefer controller route when available; gateway is a fallback base for API probing.
    printf 'https://%s' "${gateway_host}"
    return 0
  fi

  cr_url="$(oc get ansibleautomationplatform sandbox-aap -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.status.URL}' 2>/dev/null || true)"
  if [[ -n "${cr_url}" ]]; then
    printf '%s' "$(aap_normalize_url "${cr_url}")"
    return 0
  fi

  return 1
}

aap_resolve_controller_url_from_console() {
  local console_url="$1"
  # Explicit --url / workshop.env URL always wins — never override with local sandbox-aap routes.
  aap_normalize_url "${console_url}"
}

aap_api_paths() {
  printf '%s\n' \
    '/api/controller/v2/me/' \
    '/api/v2/me/' \
    '/api/controller/v2/config/' \
    '/api/v2/config/'
}

aap_token_paths() {
  printf '%s\n' \
    '/api/controller/v2/tokens/' \
    '/api/v2/tokens/'
}

aap_read_admin_password_from_cluster() {
  local secret_name="${1:-sandbox-aap-admin-password}"
  local value=""

  if ! oc get secret "${secret_name}" -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
    return 1
  fi

  value="$(oc get secret "${secret_name}" -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ -z "${value}" ]]; then
    value="$(oc get secret "${secret_name}" -n "${WORKSHOP_NAMESPACE}" \
      -o jsonpath='{.data.admin_password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  fi

  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
    return 0
  fi
  return 1
}

aap_api_reachable() {
  local base="$1"
  local user="$2"
  local pass="$3"
  local path code

  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    code="$(curl -sk --connect-timeout 3 --max-time 8 -u "${user}:${pass}" -o /dev/null -w '%{http_code}' "${base}${path}" 2>/dev/null || echo "000")"
    if [[ "${code}" == "200" ]]; then
      printf '%s' "${base}${path}"
      return 0
    fi
  done < <(aap_api_paths)
  return 1
}

aap_create_token() {
  local base="$1"
  local user="$2"
  local pass="$3"
  local description="${4:-RHDH Ansible plugin (workshop)}"

  local endpoint response token
  while IFS= read -r endpoint; do
    [[ -n "${endpoint}" ]] || continue
    endpoint="${base}${endpoint}"
    response="$(curl -sk --connect-timeout 3 --max-time 8 -u "${user}:${pass}" \
      -X POST "${endpoint}" \
      -H "Content-Type: application/json" \
      -d "{\"description\":\"${description}\"}" 2>/dev/null || true)"
    token="$(AAP_TOKEN_RESPONSE="${response}" python3 - <<'PY'
import json, os, sys
raw = os.environ.get("AAP_TOKEN_RESPONSE", "").strip()
if not raw or raw.lstrip().startswith("<"):
    sys.exit(1)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(1)
print(data.get("token") or data.get("data", {}).get("token") or "")
PY
)" || token=""
    if [[ -n "${token}" ]]; then
      printf '%s' "${token}"
      return 0
    fi
  done < <(aap_token_paths)
  return 1
}

aap_try_detect_rh_registry() {
  local secret tmp_docker parsed

  if [[ -n "${RH_REGISTRY_PULL_SECRET:-}" ]]; then
    secret="${RH_REGISTRY_PULL_SECRET}"
  else
    secret=""
    for candidate in pull-secret linked-pull-secret redhat-pull-secret; do
      if oc get secret "${candidate}" -n "${WORKSHOP_NAMESPACE}" >/dev/null 2>&1; then
        secret="${candidate}"
        break
      fi
    done
  fi

  [[ -n "${secret}" ]] || return 1

  tmp_docker="$(mktemp)"
  if ! oc get secret "${secret}" -n "${WORKSHOP_NAMESPACE}" \
    -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d >"${tmp_docker}" 2>/dev/null; then
    rm -f "${tmp_docker}"
    return 1
  fi

  parsed="$(python3 - "${tmp_docker}" <<'PY'
import base64, json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    docker = json.load(handle)
auth = docker.get("auths", {}).get("registry.redhat.io") or docker.get("auths", {}).get("https://registry.redhat.io")
if not auth:
    sys.exit(1)
raw = auth.get("auth", "")
if not raw:
    sys.exit(1)
user_pass = base64.b64decode(raw).decode("utf-8", errors="ignore")
if ":" not in user_pass:
    sys.exit(1)
user, token = user_pass.split(":", 1)
print(f"{user}|{token}")
PY
)" || parsed=""

  rm -f "${tmp_docker}"
  [[ -n "${parsed}" ]] || return 1

  RH_REGISTRY_USERNAME="${parsed%%|*}"
  RH_REGISTRY_TOKEN="${parsed#*|}"
  export RH_REGISTRY_USERNAME RH_REGISTRY_TOKEN
  return 0
}
