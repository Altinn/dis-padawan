#!/usr/bin/env bash
# Adds participants: creates participants/<name>/ from participants/_template and
# registers <name> in the syncroot (OCIRepository + Flux Kustomization).
#   scripts/add-participant.sh alice bob
#   scripts/add-participant.sh -f names.txt      # one name per line, '#' comments allowed
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$REPO_ROOT/scripts/lib.sh"
TEMPLATE="$REPO_ROOT/participants/_template"
SYNCROOT_TEMPLATE="$REPO_ROOT/scripts/templates/syncroot-participant.yaml"
SYNCROOT_BASE="$REPO_ROOT/flux/syncroot/base"
TOKEN="__NAME__"

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

names=()
if [[ "${1:-}" == "-f" ]]; then
  [[ -f "${2:-}" ]] || usage
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && names+=("$line")
  done <"$2"
else
  names=("$@")
fi
[[ ${#names[@]} -gt 0 ]] || usage

# Copies a file or directory and replaces the name token in every file.
render() {
  cp -R "$1" "$2"
  # BSD (macOS) and GNU sed differ on -i; write via a temp file instead.
  grep -rl "$TOKEN" "$2" | while IFS= read -r f; do
    sed "s/$TOKEN/$3/g" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
  done
}

status=0
for name in "${names[@]}"; do
  if [[ ! "$name" =~ $NAME_RE ]]; then
    echo "SKIP $name: must be lowercase a-z0-9 and '-', start with a letter, max 16 chars" >&2
    status=1; continue
  fi
  dest="$REPO_ROOT/participants/$name"
  syncroot_file="$SYNCROOT_BASE/$name.yaml"
  if [[ -e "$dest" || -e "$syncroot_file" ]]; then
    echo "SKIP $name: participants/$name/ or flux/syncroot/base/$name.yaml already exists" >&2
    status=1; continue
  fi

  render "$TEMPLATE" "$dest" "$name"
  render "$SYNCROOT_TEMPLATE" "$syncroot_file" "$name"

  error=""
  if grep -rq "$TOKEN" "$dest" "$syncroot_file"; then
    error="unreplaced $TOKEN left"
  else
    for overlay in kind aks; do
      if ! kubectl kustomize "$dest/overlays/$overlay" >/dev/null; then
        error="overlays/$overlay does not render"
        break
      fi
    done
  fi
  if [[ -n "$error" ]]; then
    # Remove the partial output so a re-run doesn't skip this name as "already exists".
    rm -rf "$dest" "$syncroot_file"
    echo "FAIL $name: $error (nothing created)" >&2
    status=1; continue
  fi
  echo "OK   $name -> participants/$name/, flux/syncroot/base/$name.yaml"
done

sync_syncroot_resources "$REPO_ROOT"
if ! kubectl kustomize "$REPO_ROOT/flux/syncroot/at22" >/dev/null; then
  echo "FAIL flux/syncroot/at22 does not render" >&2
  status=1
fi

exit "$status"
