#!/usr/bin/env bash
# Fallback installer when the workspace runs the base ubi9/openjdk-25 image
# without the custom Dockerfile build (user-level tools into ~/.local).
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"
export PATH="${BIN_DIR}:${PATH}"

install_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  curl -fsSL -o "${BIN_DIR}/jq" \
    https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
  chmod +x "${BIN_DIR}/jq"
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
  command -v node >/dev/null 2>&1 && return 0
  export NVM_DIR="${HOME}/.nvm"
  if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi
  # shellcheck source=/dev/null
  source "${NVM_DIR}/nvm.sh"
  nvm install 20
  nvm alias default 20
  ln -sf "${NVM_DIR}/versions/node/$(nvm version)/bin/node" "${BIN_DIR}/node" 2>/dev/null || true
  ln -sf "${NVM_DIR}/versions/node/$(nvm version)/bin/npm" "${BIN_DIR}/npm" 2>/dev/null || true
  corepack enable 2>/dev/null || true
  corepack prepare yarn@1.22.22 --activate 2>/dev/null || npm install -g yarn
}

grep -q '\.local/bin' "${HOME}/.bashrc" 2>/dev/null \
  || echo 'export PATH="${HOME}/.local/bin:${PATH}"' >>"${HOME}/.bashrc"

install_jq
install_oc
install_helm
install_node

echo "JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-25}"
java -version 2>&1 | head -1
