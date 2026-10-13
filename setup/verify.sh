#!/usr/bin/env bash
# Pre-training environment check (macOS / Linux). Run it on the network you normally use to reach AKS.
#   ./setup/verify.sh            # all checks
#   ./setup/verify.sh --skip-aks # only local checks (tools, Podman, images)
# Checks that everything is ready; it does not create anything. The kind cluster is created in Lab 1.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Parsed, not sourced: values may contain <placeholders>.
while IFS='=' read -r key value; do
  if [[ "$key" =~ ^[A-Z_]+$ ]]; then printf -v "$key" '%s' "$value"; fi
done <"${SCRIPT_DIR}/config.env"

SKIP_AKS=false
[[ "${1:-}" == "--skip-aks" ]] && SKIP_AKS=true

FAILED=0
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILED=$((FAILED + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# check_version <name> <expected> <actual-version-output>
check_version() {
  if [[ "$3" == *"$2"* ]]; then ok "$1 $2"; else warn "$1: found $3 (training tested with $2; usually fine)"; fi
}

section "Tools"
for tool in git kind kubectl az kubelogin; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not found on PATH (run setup/install-macos.sh)"
done
command -v kind >/dev/null 2>&1 && check_version kind "$KIND_VERSION" "$(kind version)"
command -v kubectl >/dev/null 2>&1 && check_version kubectl "$KUBECTL_VERSION" "$(kubectl version --client 2>/dev/null | head -1)"
command -v kubelogin >/dev/null 2>&1 && check_version kubelogin "$KUBELOGIN_VERSION" "$(kubelogin --version 2>/dev/null | tr '\n' ' ')"
command -v flux >/dev/null 2>&1 && check_version flux "$FLUX_VERSION" "$(flux version --client 2>/dev/null)" || warn "flux not found (optional)"
command -v hey >/dev/null 2>&1 && ok "hey" || warn "hey not found (optional, Lab 4)"
if command -v az >/dev/null 2>&1; then
  AZ_VER="$(az version --query '"azure-cli"' -o tsv 2>/dev/null)"
  if [[ "$(printf '%s\n%s\n' "$AZ_CLI_MIN_VERSION" "$AZ_VER" | sort -V | head -1)" == "$AZ_CLI_MIN_VERSION" ]]; then
    ok "az $AZ_VER"
  else
    fail "az $AZ_VER is older than $AZ_CLI_MIN_VERSION"
  fi
fi

section "Podman"
if ! command -v podman >/dev/null 2>&1; then
  fail "podman not found on PATH (see setup/README.md)"
elif ! podman info >/dev/null 2>&1; then
  fail "podman is not running: podman machine start"
else
  ok "podman is running"
  # MemTotal is what the machine's kernel sees, a bit below the configured size,
  # so a 4096 MiB machine reports roughly 3.8 GiB. 3500 MiB leaves room for that.
  MEM_MIB=$(( $(podman info --format '{{.Host.MemTotal}}' 2>/dev/null || echo 0) / 1024 / 1024 ))
  if (( MEM_MIB >= 3500 )); then
    ok "podman machine memory ${MEM_MIB} MiB"
  else
    fail "podman machine has ${MEM_MIB} MiB memory, kind needs 4096: podman machine stop; podman machine set --memory 4096; podman machine start"
  fi
fi
if [[ "${KIND_EXPERIMENTAL_PROVIDER:-}" != "podman" ]]; then
  fail "KIND_EXPERIMENTAL_PROVIDER is not set to podman in your shell (see setup/README.md)"
fi

section "Images (kind node pre-pulled; podinfo pull = registry check)"
# Read the pinned node image from kind-config.yaml so there is one source of truth.
KIND_NODE_IMAGE="$(awk '$1 == "image:" {print $2; exit}' "${SCRIPT_DIR}/kind-config.yaml")"
for image in "$KIND_NODE_IMAGE" "$PODINFO_IMAGE"; do
  if podman pull -q "$image" >/dev/null 2>&1; then
    ok "pulled ${image%%@*}"
  else
    fail "could not pull $image (network/proxy/DNS in the Podman machine?)"
  fi
done

if [[ "$SKIP_AKS" == false ]]; then
  section "AKS and Azure"
  if az account show >/dev/null 2>&1; then
    ok "az logged in ($(az account show --query user.name -o tsv))"
  else
    fail "not logged in: run 'az login'"
  fi
  if kubectl config get-contexts "$AKS_CONTEXT" >/dev/null 2>&1; then
    AKS_SERVER="$(kubectl config view --minify --context "$AKS_CONTEXT" -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)"
    if [[ "$AKS_SERVER" == *".privatelink."* ]]; then
      fail "kubeconfig uses the private FQDN ($AKS_SERVER): re-run the az aks get-credentials command from the invitation email"
    else
      # Any HTTP status (even 401) proves the API server is reachable; 000 means no connection.
      HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$AKS_SERVER/healthz")"
      if [[ "$HTTP_CODE" == "000" ]]; then
        fail "AKS API $AKS_SERVER not reachable (can you reach your other AKS clusters from this machine?)"
      else
        ok "AKS API reachable ($AKS_SERVER)"
      fi
    fi
    if [[ "$(kubectl --context "$AKS_CONTEXT" auth can-i list pods -n "$TRAINING_NAMESPACE" 2>/dev/null)" == "yes" ]]; then
      ok "kubectl can list pods in $TRAINING_NAMESPACE on AKS"
    else
      fail "no access to $TRAINING_NAMESPACE on $AKS_CONTEXT (group membership? kubelogin?)"
    fi
  else
    fail "kube context '$AKS_CONTEXT' missing: see setup/README.md 'Connect to AKS'"
  fi
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  printf '\033[32mAll required checks passed.\033[0m\n'
else
  printf '\033[31m%d check(s) failed.\033[0m Send the output above to the trainer.\n' "$FAILED"
  exit 1
fi
