#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"
export PATH="${BIN_DIR}:${PATH}"

# Workshop requires Node.js 22.12+ (AAP Management plugin / yargs@18).
node_version_ok() {
  command -v node >/dev/null 2>&1 || return 1
  node -e 'const [maj,min]=process.versions.node.split(".").map(Number); process.exit((maj===22&&min>=12)||maj>=23?0:1)'
}

ensure_shell_path() {
  local line='export PATH="${HOME}/.local/bin:${PATH}"'
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    [[ -f "${rc}" ]] || touch "${rc}"
    grep -qF '.local/bin' "${rc}" 2>/dev/null || echo "${line}" >>"${rc}"
  done
}

ensure_nvm_shell_init() {
  local nvm_line='export NVM_DIR="${HOME}/.nvm"; [ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"'
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    [[ -f "${rc}" ]] || touch "${rc}"
    grep -qF 'nvm.sh' "${rc}" 2>/dev/null || echo "${nvm_line}" >>"${rc}"
  done
}

source_nvm() {
  export NVM_DIR="${HOME}/.nvm"
  if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "${NVM_DIR}/nvm.sh"
  fi
}

symlink_node_to_local_bin() {
  source_nvm
  if command -v node >/dev/null 2>&1 && [[ -n "${NVM_DIR:-}" ]]; then
    local node_dir="${NVM_DIR}/versions/node/$(nvm version)"
    if [[ -d "${node_dir}/bin" ]]; then
      ln -sf "${node_dir}/bin/node" "${BIN_DIR}/node"
      ln -sf "${node_dir}/bin/npm" "${BIN_DIR}/npm"
      ln -sf "${node_dir}/bin/npx" "${BIN_DIR}/npx"
    fi
  fi
}

install_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  curl -fsSL -o "${BIN_DIR}/jq" \
    https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
  chmod +x "${BIN_DIR}/jq"
}

install_pyyaml_via_os_packages() {
  local -a attempted=()
  local mgr

  for mgr in microdnf dnf; do
    command -v "${mgr}" >/dev/null 2>&1 || continue

    if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
      attempted+=("sudo ${mgr} install -y python3-pyyaml")
      if sudo "${mgr}" install -y python3-pyyaml >/dev/null 2>&1 \
        && python3 -c 'import yaml' 2>/dev/null; then
        return 0
      fi
    fi

    attempted+=("${mgr} install -y python3-pyyaml")
    if "${mgr}" install -y python3-pyyaml >/dev/null 2>&1 \
      && python3 -c 'import yaml' 2>/dev/null; then
      return 0
    fi
  done

  printf '%s\n' "${attempted[@]}"
  return 1
}

install_pyyaml() {
  python3 -c 'import yaml' 2>/dev/null && return 0
  echo "Installing PyYAML for workshop scripts..."

  local -a attempted=()
  local os_attempted

  os_attempted="$(install_pyyaml_via_os_packages || true)"
  if [[ -n "${os_attempted}" ]]; then
    while IFS= read -r line; do
      [[ -n "${line}" ]] && attempted+=("${line}")
    done <<<"${os_attempted}"
  fi
  if python3 -c 'import yaml' 2>/dev/null; then
    return 0
  fi

  attempted+=("python3 -m ensurepip + python3 -m pip install pyyaml")

  if ! python3 -m pip --version >/dev/null 2>&1; then
    python3 -m ensurepip --user --default-pip 2>/dev/null \
      || python3 -m ensurepip --default-pip 2>/dev/null \
      || true
  fi

  if python3 -m pip --version >/dev/null 2>&1; then
    local -a pip_install=(python3 -m pip install)
    if ! python3 -c 'import sys; raise SystemExit(0 if sys.prefix != sys.base_prefix else 1)' 2>/dev/null; then
      pip_install+=(--user)
      if python3 -m pip install --help 2>/dev/null | grep -q -- '--break-system-packages'; then
        pip_install+=(--break-system-packages)
      fi
    fi
    pip_install+=(-q pyyaml)
    "${pip_install[@]}" || true
  else
    attempted+=("python3 -m pip install --user pyyaml (pip unavailable after ensurepip)")
  fi

  if python3 -c 'import yaml' 2>/dev/null; then
    return 0
  fi

  echo "ERROR: failed to install PyYAML. Attempted:" >&2
  for method in "${attempted[@]}"; do
    echo "  - ${method}" >&2
  done
  echo "Install manually (RHEL/UBI): sudo dnf install -y python3-pyyaml" >&2
  echo "  or: sudo microdnf install -y python3-pyyaml" >&2
  return 1
}

install_oc() {
  command -v oc >/dev/null 2>&1 && return 0
  curl -fsSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz \
    | tar -xz -C "${BIN_DIR}" oc kubectl
  chmod +x "${BIN_DIR}/oc" "${BIN_DIR}/kubectl"
}

install_helm() {
  command -v helm >/dev/null 2>&1 && return 0
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL https://get.helm.sh/helm-v3.16.3-linux-amd64.tar.gz \
    | tar -xz -C "${tmp}"
  mv "${tmp}/linux-amd64/helm" "${BIN_DIR}/helm"
  chmod +x "${BIN_DIR}/helm"
  rm -rf "${tmp}"
}

install_node() {
  if node_version_ok; then
    symlink_node_to_local_bin
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    echo "Node.js $(node --version) does not meet workshop requirement (>=22.12); installing Node.js 22 via nvm..."
  else
    echo "Node.js not found; installing Node.js 22 via nvm..."
  fi
  export NVM_DIR="${HOME}/.nvm"
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi
  source_nvm
  nvm install 22
  nvm alias default 22
  nvm use default
  symlink_node_to_local_bin
  ensure_nvm_shell_init
  corepack enable 2>/dev/null || true
  corepack prepare yarn@1.22.22 --activate 2>/dev/null || npm install -g yarn
}

ensure_shell_path
install_jq
install_pyyaml
install_oc
install_helm
install_node

if command -v java >/dev/null 2>&1; then
  export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
echo "JAVA_HOME=${JAVA_HOME:-not set}"
java -version 2>&1 | head -1
echo "node $(node --version 2>/dev/null || echo missing)"
echo "npm $(npm --version 2>/dev/null || echo missing)"
