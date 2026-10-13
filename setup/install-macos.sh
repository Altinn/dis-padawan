#!/usr/bin/env bash
# Installs the CLI tools for the training into ~/.local/bin (macOS).
# Tools already on your PATH are left alone, whatever their version; missing
# tools are installed at the versions pinned in config.env.
# Podman is checked, not installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Parsed, not sourced: values may contain <placeholders>.
while IFS='=' read -r key value; do
  if [[ "$key" =~ ^[A-Z_]+$ ]]; then printf -v "$key" '%s' "$value"; fi
done <"${SCRIPT_DIR}/config.env"

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"

case "$(uname -m)" in
  arm64 | aarch64) ARCH=arm64 ;;
  x86_64) ARCH=amd64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m %s\n' "$*"; }

# verify_sha256 <file> <expected-hash>
verify_sha256() {
  local actual
  actual="$(shasum -a 256 "$1" | awk '{print $1}')"
  if [[ "$actual" != "$2" ]]; then
    echo "Checksum mismatch for $1: expected $2, got $actual" >&2
    exit 1
  fi
}

install_kind() {
  info "kind ${KIND_VERSION}"
  local base="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-darwin-${ARCH}"
  curl -fsSLo "$TMP/kind" "$base"
  verify_sha256 "$TMP/kind" "$(curl -fsSL "${base}.sha256sum" | awk '{print $1}')"
  install -m 0755 "$TMP/kind" "$BIN_DIR/kind"
}

install_kubectl() {
  info "kubectl ${KUBECTL_VERSION}"
  local base="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/darwin/${ARCH}/kubectl"
  curl -fsSLo "$TMP/kubectl" "$base"
  verify_sha256 "$TMP/kubectl" "$(curl -fsSL "${base}.sha256")"
  install -m 0755 "$TMP/kubectl" "$BIN_DIR/kubectl"
}

install_kubelogin() {
  info "kubelogin ${KUBELOGIN_VERSION}"
  local base="https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin-darwin-${ARCH}.zip"
  curl -fsSLo "$TMP/kubelogin.zip" "$base"
  verify_sha256 "$TMP/kubelogin.zip" "$(curl -fsSL "${base}.sha256" | awk '{print $1}')"
  unzip -q -o "$TMP/kubelogin.zip" -d "$TMP/kubelogin"
  install -m 0755 "$TMP/kubelogin/bin/darwin_${ARCH}/kubelogin" "$BIN_DIR/kubelogin"
}

install_flux() {
  info "flux ${FLUX_VERSION}"
  local file="flux_${FLUX_VERSION}_darwin_${ARCH}.tar.gz"
  local base="https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}"
  curl -fsSLo "$TMP/$file" "$base/$file"
  verify_sha256 "$TMP/$file" "$(curl -fsSL "$base/flux_${FLUX_VERSION}_checksums.txt" | awk -v f="$file" '$2 == f {print $1}')"
  tar -xzf "$TMP/$file" -C "$TMP" flux
  install -m 0755 "$TMP/flux" "$BIN_DIR/flux"
}

# install_if_missing <tool> <install-function>
install_if_missing() {
  if command -v "$1" >/dev/null 2>&1; then
    info "$1 already installed ($(command -v "$1")), keeping it"
  else
    "$2"
  fi
}

install_if_missing kind install_kind
install_if_missing kubectl install_kubectl
install_if_missing kubelogin install_kubelogin
install_if_missing flux install_flux

if ! command -v az >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    info "azure-cli (Homebrew)"
    brew install azure-cli
  else
    warn "az CLI not found and Homebrew missing. Install: https://learn.microsoft.com/cli/azure/install-azure-cli-macos"
  fi
fi

if ! command -v hey >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    info "hey (Homebrew, load generator for Lab 4)"
    brew install hey
  else
    warn "hey not found (optional, Lab 4). Install with Homebrew: brew install hey"
  fi
fi

if ! command -v podman >/dev/null 2>&1; then
  warn "podman not found. Install Podman or Podman Desktop and create a machine with at least 4 GB memory (see setup/README.md)."
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH. Add this to ~/.zshrc and open a new terminal:"
     echo "    export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

info "Done. Next: ./setup/verify.sh"
