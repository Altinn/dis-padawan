# Participants

Each participant owns exactly one folder: `participants/<name>/`. **Only change files in your own folder.** Other people's folders deploy to the same AKS namespace.

```
participants/<name>/
  base/               # podinfo: Deployment, Service, ConfigMap (shared by both environments)
  overlays/
    kind/             # local cluster: namespace + demo-secret from secretGenerator
    aks/              # AKS: name prefix + owner label, identity + Key Vault, ExternalSecret, HTTPRoute
```

| | kind (morning) | AKS (afternoon) |
|---|---|---|
| Who applies it | you: `kubectl apply -k participants/<name>/overlays/kind` | Flux, after `git push` → workflow → ACR |
| Names | `podinfo`, `podinfo-config`, … | `<name>-podinfo`, `<name>-podinfo-config`, … |
| `demo-secret` | `secretGenerator` with a literal value | `ExternalSecret` reading secret `demo-api-key` from your own Key Vault |
| Reach the app | `kubectl port-forward svc/podinfo 9898:9898 -n product-dis-padawan` | `https://dis-padawan-<name>.at22.dis-core.altinn.cloud` |

Preview what Flux will apply: `kubectl kustomize participants/<name>/overlays/aks`

Your AKS overlay starts with all resources commented out, so pushing during the kind labs deploys nothing to AKS. Lab 3 enables them.

Pushing when others have pushed first:

```sh
git pull --rebase
git push
```

## `_template/`

Trainer-owned source for new folders. `__NAME__` is replaced by `scripts/add-participant.sh`. The workflow ignores it.
