# Lab 3 — Deploy to AKS with git push and Flux

**Time:** 75 min · **Where:** AKS (`product-dis-training`), via git

## Goal

Deploy your app to AKS without running `kubectl apply`: you push, a workflow publishes your folder to ACR, and Flux applies it. Your app gets its secret from your own Key Vault and is reachable on your own hostname.

```
git push ─► workflow "Publish participants" ─► altinncr.azurecr.io/dis-training/<name>:main
                                                        │
               Flux (OCIRepository + Kustomization <name>) ◄┘  applies overlays/aks every 2 min
```

## Before you start

- Set `NAME` in every terminal (`NAME=alice` / `$NAME = "alice"`).
- You did [setup step 3](../setup/README.md#3-connect-to-aks) (AKS credentials).

## Steps

### 1. Context and access (5 min)

Switch to AKS and make the training namespace your default:

```sh
kubectl config use-context dis-core-at22-aks
kubectl config set-context --current --namespace product-dis-training
kubectl config current-context
```

From now on, **check your context** before running a command: `kind-k8s-training` is your laptop, `dis-core-at22-aks` is the shared cluster.

You're admin in this namespace:

```sh
kubectl auth can-i create deployments       # yes
kubectl get kustomizations,ocirepositories  # one pair per participant, created by the trainer's syncroot
```

You *could* `kubectl apply` here. Don't: anything that isn't in git is undone by Flux within 2 minutes. And everyone shares this namespace, so be careful with `delete`.

### 2. Round 1: identity and Key Vault (10 min). Do this first

Creating the identity and Key Vault in Azure takes a moment, so start it now and keep working while it happens.

Open `participants/<name>/overlays/aks/kustomization.yaml`. Uncomment the two Round 1 lines:

```yaml
resources:
  - applicationidentity.yaml
  - vault.yaml
```

Render and check: two objects, both named `<name>-podinfo`, and the Vault's `identityRef` points at the identity.

```sh
kubectl kustomize "participants/$NAME/overlays/aks"
```

Commit and push:

```sh
git add "participants/$NAME"
git commit -m "lab 3 round 1 ($NAME)"
git pull --rebase
git push
```

Follow it: GitHub → **Actions** → **Publish participants** → your job. When it's green, Flux picks it up within a minute:

```sh
kubectl get ocirepository "$NAME"           # READY True, REVISION main@sha1:…
kubectl get kustomization "$NAME" -w        # READY True: "Applied revision …"
kubectl get applicationidentities,vaults -l "owner=$NAME"
```

What the operators create from these two objects:

```sh
kubectl get serviceaccount "$NAME-podinfo" -o yaml   # annotation azure.workload.identity/client-id
kubectl get secretstores                             # <name>-podinfo-secret-store, from the Vault operator
kubectl describe vault "$NAME-podinfo"               # conditions; status.azureName is your vault's name in Azure
```

### 3. While Azure works (15 min)

Read `overlays/aks/externalsecret.yaml` and `overlays/aks/httproute.yaml`:

- The ExternalSecret reads `demo-api-key` from your vault (through the SecretStore the Vault operator made) and writes a Kubernetes Secret named `demo-secret`, the same name the Deployment already uses on kind.
- The HTTPRoute attaches to the platform's Gateway and sends `https://dis-training-<name>.at22.dis-core.altinn.cloud` to your Service.

Compare what the two overlays produce from the same base:

```sh
kubectl kustomize "participants/$NAME/overlays/kind"
kubectl kustomize "participants/$NAME/overlays/aks"
```

Once you uncomment everything (Round 2), the AKS output differs in these ways. Ask the trainer why each one is there:

| | kind | AKS |
|---|---|---|
| Names | `podinfo` | `<name>-podinfo`: `namePrefix`, because the namespace is shared |
| Labels and selectors | `app.kubernetes.io/name` | also `owner: <name>`, so your Service never selects someone else's pods |
| Image | `ghcr.io/stefanprodan/podinfo` | `altinncr.azurecr.io/…`: `images:` in the overlay |
| `demo-secret` | `secretGenerator`, value in git | `ExternalSecret`, value in Key Vault |
| Way in | `kubectl port-forward` | `HTTPRoute` on the shared Gateway |

`kustomizeconfig.yaml` is why the prefix also lands in references Kustomize doesn't know about: the HTTPRoute's `backendRefs`, the Vault's `identityRef`, the Deployment's reference to the ExternalSecret's Secret.

### 4. Create your secret (5 min)

When the Vault is Ready, put a secret in it. Your vault's Azure name is in its status:

```sh
VAULT=$(kubectl get vault "$NAME-podinfo" -o jsonpath='{.status.azureName}')                # bash
```

```powershell
$VAULT = kubectl get vault "$NAME-podinfo" -o jsonpath='{.status.azureName}'                # PowerShell
```

```sh
az keyvault secret set --vault-name "$VAULT" --name demo-api-key --value "my-very-secret-$NAME"
```

`Forbidden`? Your access comes from a role assignment the operator just created. It can take a few minutes to take effect: wait and retry.

### 5. Round 2: podinfo (15 min)

Uncomment the Round 2 lines:

```yaml
  - ../../base
  - externalsecret.yaml
  - httproute.yaml
```

Render, and check the names line up: Deployment `envFrom` → `<name>-demo-secret`, HTTPRoute `backendRefs` → `<name>-podinfo`. Then commit, `git pull --rebase`, push, and follow the workflow again.

Follow the chain on the cluster:

```sh
kubectl get kustomization "$NAME" -w                 # Applied revision …
kubectl get externalsecret "$NAME-demo-secret"       # STATUS SecretSynced
kubectl get secret "$NAME-demo-secret"               # created by External Secrets
kubectl get deployments,pods -l "owner=$NAME"
kubectl describe httproute "$NAME-podinfo"           # Status → Parents: Accepted True, ResolvedRefs True
```

Open `https://dis-training-<name>.at22.dis-core.altinn.cloud` in a browser, then `/env`: `API_KEY` is the value you put in Key Vault.

```sh
curl "https://dis-training-$NAME.at22.dis-core.altinn.cloud/env"         # bash
```

```powershell
curl.exe "https://dis-training-$NAME.at22.dis-core.altinn.cloud/env"     # PowerShell
```

### 6. Change something, the GitOps way (10 min)

Give AKS its own UI message, without touching the base (kind keeps its own). Add this to `overlays/aks/kustomization.yaml`:

```yaml
configMapGenerator:
  - name: podinfo-config
    behavior: merge
    literals:
      - PODINFO_UI_MESSAGE=Hello from AKS
```

`behavior: merge` changes one value of the base's generated ConfigMap. Render: the ConfigMap gets a new hash, so the Deployment rolls out. Push, then:

```sh
kubectl rollout status deployment "$NAME-podinfo" -w
```

Reload your hostname.

**Checkpoint:** you changed a running app on a shared cluster without a single `kubectl apply`.

## When something's wrong

| Symptom | Look at |
|---|---|
| Workflow red at *Validate manifests* | Render locally with `kubectl kustomize`; fix the YAML |
| `kustomization` READY False | `kubectl describe kustomization "$NAME"`: the message says which object failed and why |
| `ocirepository` READY False | Did the workflow publish? Is it green? |
| Vault not Ready | `kubectl describe vault "$NAME-podinfo"`; ask the trainer |
| ExternalSecret `SecretSyncedError` | `kubectl describe externalsecret "$NAME-demo-secret"`: did you create `demo-api-key` in **your** vault? |
| HTTPRoute not Accepted, or the hostname gives 404 | `kubectl describe httproute "$NAME-podinfo"`; ask the trainer |

## Stretch task

- **Drift correction.** Scale by hand and watch Flux put it back within ~2 minutes:

  ```sh
  kubectl scale deployment "$NAME-podinfo" --replicas=1
  kubectl get deployment "$NAME-podinfo" -w
  ```

  (Deleting a pod doesn't show this: the ReplicaSet replaces it, not Flux.)
- **Prune.** Delete your HTTPRoute with kubectl and watch Flux recreate it. Then remove `httproute.yaml` from `resources` in git, push, and watch Flux delete it. Put it back afterwards.
- With the flux CLI: `flux get kustomizations`, `flux events --for Kustomization/$NAME`, `flux tree kustomization $NAME`.

## Solution

[`labs/solutions/lab-3/`](solutions/lab-3/): your folder as it should look after this lab.
