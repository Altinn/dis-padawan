#!/usr/bin/env bash
# Breaks your podinfo on purpose. Your job: find out what's wrong with
# kubectl get / describe / events / logs [--previous] / exec, then fix it.
#
#   scripts/break.sh kind              # random scenario on your kind cluster
#   scripts/break.sh kind 3            # a specific scenario
#   scripts/break.sh aks <name>        # random scenario on AKS (suspends your Flux Kustomization)
#   scripts/break.sh aks <name> 6
#   scripts/break.sh hint <number>     # a nudge, if you're stuck
#
# Fix on kind: kubectl apply -k participants/<name>/overlays/kind
# Fix on AKS:  flux resume kustomization <name> -n product-dis-padawan
#              (Flux re-applies what's in git; that's the GitOps way to undo a manual change)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Parsed, not sourced: values may contain <placeholders>.
while IFS='=' read -r key value; do
  if [[ "$key" =~ ^[A-Z_]+$ ]]; then printf -v "$key" '%s' "$value"; fi
done <"$REPO_ROOT/setup/config.env"

NS="$TRAINING_NAMESPACE"
KIND_SCENARIOS=(1 2 3 4 5)
AKS_SCENARIOS=(1 2 3 4 5 6 7)

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

hint() {
  case "$1" in
    1) echo "Look at the pod's events: kubectl describe pod. What is it waiting for?" ;;
    2) echo "The container starts and stops. What did it say before it died? kubectl logs --previous" ;;
    3) echo "Pods are Running but not Ready. Which check decides Ready, and what does it call?" ;;
    4) echo "Check 'Last State' and 'Reason' in kubectl describe pod. Compare with the container's limits." ;;
    5) echo "The pods look fine. Does the Service find them? kubectl describe service podinfo (Selector, Endpoints), and compare with kubectl get pods --show-labels." ;;
    6) echo "Pods can't start their container. Follow the chain: ExternalSecret status -> Secret -> pod events." ;;
    7) echo "Pods and Service are fine. Is the route attached to the gateway? kubectl describe httproute" ;;
    *) echo "No such scenario" >&2; exit 1 ;;
  esac
}

# patch <kind/name> <json|merge> <patch-json>. Uses a patch file: no shell quoting surprises.
patch() {
  local f
  f="$(mktemp)"
  printf '%s' "$3" >"$f"
  kubectl --context "$CTX" -n "$NS" patch "$1" --type "$2" --patch-file "$f" >/dev/null
  rm -f "$f"
}

[[ $# -ge 1 ]] || usage
case "$1" in
  hint) [[ $# -eq 2 ]] || usage; hint "$2"; exit 0 ;;
  kind)
    CTX="kind-k8s-training"; PREFIX=""; SCENARIOS=("${KIND_SCENARIOS[@]}"); CHOICE="${2:-}" ;;
  aks)
    [[ $# -ge 2 ]] || usage
    CTX="$AKS_CONTEXT"; PREFIX="$2-"; SCENARIOS=("${AKS_SCENARIOS[@]}"); CHOICE="${3:-}" ;;
  *) usage ;;
esac

if [[ -z "$CHOICE" ]]; then
  CHOICE="${SCENARIOS[RANDOM % ${#SCENARIOS[@]}]}"
elif [[ ! " ${SCENARIOS[*]} " == *" $CHOICE "* ]]; then
  echo "Scenario $CHOICE is not available on $1 (available: ${SCENARIOS[*]})" >&2
  exit 1
fi

DEPLOY="deployment/${PREFIX}podinfo"
kubectl --context "$CTX" -n "$NS" get "$DEPLOY" >/dev/null || {
  echo "No $DEPLOY in $NS on $CTX. Deploy podinfo first." >&2
  exit 1
}

if [[ "$1" == aks ]]; then
  # Otherwise Flux reverts the break within its 2-minute drift check.
  patch "kustomizations.kustomize.toolkit.fluxcd.io/$2" merge '{"spec":{"suspend":true}}'
  echo "Your Flux Kustomization '$2' is suspended, so Flux won't undo the break."
fi

case "$CHOICE" in
  1) # ImagePullBackOff: a tag that doesn't exist
    image="$(kubectl --context "$CTX" -n "$NS" get "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
    patch "$DEPLOY" json "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"${image%:*}:6.15.99\"}]" ;;
  2) # CrashLoopBackOff: unknown flag, podinfo exits with code 2
    patch "$DEPLOY" json '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--colour=red"}]' ;;
  3) # Readiness probe on a path that doesn't exist: Running, never Ready
    patch "$DEPLOY" json '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/ready"}]' ;;
  4) # OOMKilled: loads 256 MB into memory with a 128Mi limit
    patch "$DEPLOY" json '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--stress-memory=256"}]' ;;
  5) # Service selects no pods
    patch "service/${PREFIX}podinfo" merge '{"spec":{"selector":{"app.kubernetes.io/name":"podinfo-api"}}}' ;;
  6) # ExternalSecret reads a key that doesn't exist; Secret gone; new pods can't start
    patch "externalsecret/${PREFIX}demo-secret" json '[{"op":"replace","path":"/spec/data/0/remoteRef/key","value":"demo-apikey"}]'
    kubectl --context "$CTX" -n "$NS" delete secret "${PREFIX}demo-secret" --ignore-not-found >/dev/null
    kubectl --context "$CTX" -n "$NS" rollout restart "$DEPLOY" >/dev/null ;;
  7) # HTTPRoute points at a gateway listener that doesn't exist
    patch "httproute/${PREFIX}podinfo" json '[{"op":"add","path":"/spec/parentRefs/0/sectionName","value":"public"}]' ;;
esac

echo "Broke scenario #$CHOICE. Something is wrong with your podinfo now. Find out what."
echo "Stuck? scripts/break.sh hint $CHOICE"
