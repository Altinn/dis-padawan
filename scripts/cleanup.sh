#!/usr/bin/env bash
# Removes participants, in two phases.
#
# 1. Repo (default): delete flux/syncroot/base/<name>.yaml and participants/<name>/.
#      scripts/cleanup.sh alice bob
#      scripts/cleanup.sh --keep-folder alice      # keep participants/alice/
#    Commit and push. The syncroot publish removes the participant's OCIRepository and
#    Flux Kustomization; prune: true then deletes everything that Kustomization applied,
#    including the Vault and ApplicationIdentity (the operators remove the Azure resources).
#
# 2. Azure, once Flux has pruned (dry run unless --yes):
#      scripts/cleanup.sh --azure alice bob
#      scripts/cleanup.sh --azure --yes alice bob
#    Deletes the ACR repository dis-padawan/<name>.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$REPO_ROOT/scripts/lib.sh"
# Parsed, not sourced: values may contain <placeholders>.
while IFS='=' read -r key value; do
  if [[ "$key" =~ ^[A-Z_]+$ ]]; then printf -v "$key" '%s' "$value"; fi
done <"$REPO_ROOT/setup/config.env"

ACR_NAME=altinncr
ACR_REPOSITORY_PREFIX=dis-padawan

AZURE=false
EXECUTE=false
KEEP_FOLDER=false
names=()
for arg in "$@"; do
  case "$arg" in
    --azure) AZURE=true ;;
    --yes) EXECUTE=true ;;
    --keep-folder) KEEP_FOLDER=true ;;
    -*) echo "unknown flag $arg" >&2; exit 1 ;;
    *) names+=("$arg") ;;
  esac
done
[[ ${#names[@]} -gt 0 ]] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

if [[ "$AZURE" == false ]]; then
  for name in "${names[@]}"; do
    rm -f "$REPO_ROOT/flux/syncroot/base/$name.yaml"
    [[ "$KEEP_FOLDER" == true ]] || rm -rf "${REPO_ROOT:?}/participants/$name"
    echo "removed $name from the syncroot$([[ "$KEEP_FOLDER" == true ]] || echo " and participants/")"
  done
  sync_syncroot_resources "$REPO_ROOT"
  kubectl kustomize "$REPO_ROOT/flux/syncroot/at22" >/dev/null
  cat <<EOF

Next:
  1. git add -A flux/syncroot participants && git commit -m "Remove participants: ${names[*]}" && git push
  2. Wait until Flux has pruned (no Kustomization left for these names):
       kubectl --context $AKS_CONTEXT -n $TRAINING_NAMESPACE get kustomizations.kustomize.toolkit.fluxcd.io
  3. scripts/cleanup.sh --azure ${names[*]}
EOF
  exit 0
fi

if [[ "$EXECUTE" == true ]] && grep -q '<' <<<"$AKS_CONTEXT"; then
  echo "Refusing to run: placeholders in setup/config.env are not filled in." >&2
  exit 1
fi

run() {
  echo "+ $*"
  if [[ "$EXECUTE" == true ]]; then "$@" || echo "  (failed, continuing)" >&2; fi
}

for name in "${names[@]}"; do
  echo "## $name"
  if [[ "$EXECUTE" == true ]] &&
     kubectl --context "$AKS_CONTEXT" -n "$TRAINING_NAMESPACE" get kustomizations.kustomize.toolkit.fluxcd.io "$name" >/dev/null 2>&1; then
    echo "  SKIP: Flux Kustomization $name still exists; finish phase 1 and wait for Flux to prune" >&2
    continue
  fi
  run az acr repository delete --name "$ACR_NAME" --repository "$ACR_REPOSITORY_PREFIX/$name" --yes
  # Anything left with the owner label means prune missed it.
  run kubectl --context "$AKS_CONTEXT" -n "$TRAINING_NAMESPACE" get all,externalsecrets,httproutes,vaults,applicationidentities -l "owner=$name"
done

[[ "$EXECUTE" == true ]] || echo "Dry run. Re-run with --yes to execute."
