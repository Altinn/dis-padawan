# dis-training

Hands-on Kubernetes / AKS training. In the morning you run podinfo on a local **kind** cluster with `kubectl apply -k`. In the afternoon you deploy the same app to **AKS** with `git push` → GitHub workflow → OCI artifact in ACR → **Flux**.

## Participants: start here

1. Do the [setup](setup/README.md) **before** the training day and run the verify script.
2. Your folder is `participants/<name>/`. The trainer creates it. Only change files in your own folder.
3. Follow the [labs](labs/README.md).

## Layout

```
.github/workflows/   publish workflows: syncroot + changed participants
participants/
  _template/         source for participant folders (trainer)
  <name>/            your app: base/ + overlays/kind + overlays/aks
flux/syncroot/       syncroot (artifact dis-training/syncroot:at22): OCIRepository + Flux Kustomization per participant (trainer)
setup/               pinned versions, kind config, install + verify scripts (macOS + Windows)
labs/                lab guides
scripts/             add-participant / cleanup (trainer); break.sh / break.ps1 (participants, break-fix)
```

## Trainer quick reference

```sh
scripts/add-participant.sh alice bob          # folder + syncroot entry; or: -f names.txt
kubectl kustomize flux/syncroot/at22
kubectl kustomize participants/alice/overlays/aks
scripts/cleanup.sh alice bob                  # removes syncroot entry + folder; commit, push, then:
scripts/cleanup.sh --azure alice bob          # ACR repository (dry run; add --yes)
```

Pinned versions: [`setup/config.env`](setup/config.env). Open placeholders (`<...>`) need to be filled in before the training: `grep -rn '<[a-z-]*>' --include='*.yaml' --include='*.env' --include='*.sh' .`
