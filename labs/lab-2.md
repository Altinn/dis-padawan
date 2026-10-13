# Lab 2 — Configuration, probes and break-fix

**Time:** 60 min · **Where:** your kind cluster

## Goal

Configure the app, understand health checks, and diagnose the common pod failures.

## Before you start

Same as Lab 1: set `NAME` in every terminal (`NAME=alice` in bash, `$NAME = "alice"` in PowerShell) and check you're on kind:

```sh
kubectl config current-context        # kind-k8s-training
```

Keep a port-forward running in a second terminal: `kubectl port-forward svc/podinfo 9898:9898`. When it stops after a rollout (its pod is gone), start it again.

## Steps

### 1. ConfigMap (10 min)

Change `PODINFO_UI_MESSAGE` in `participants/<name>/base/configmap.yaml` to something of your own, then apply:

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl get pods                      # look at AGE
```

Reload http://localhost:9898. The old message is still there, and the pods weren't restarted. The ConfigMap changed, but podinfo reads its environment variables **only when the container starts**.

Restart by hand:

```sh
kubectl rollout restart deployment podinfo
```

Now your message shows (restart the port-forward). A manual restart is easy to forget. Let Kustomize handle it instead:

1. Delete `base/configmap.yaml` and remove it from `resources` in `base/kustomization.yaml`.
2. Add a generator to `base/kustomization.yaml`:

   ```yaml
   configMapGenerator:
     - name: podinfo-config
       literals:
         - PODINFO_UI_MESSAGE=Hello from <your name>
         - PODINFO_UI_COLOR=#34577c
   ```

3. Render and look for the ConfigMap name, and for the Deployment's `configMapRef`:

   ```sh
   kubectl kustomize "participants/$NAME/overlays/kind"
   ```

The name is now `podinfo-config-<hash>`. The hash comes from the content: change a value, and the name changes. The Deployment then refers to a new name, which is a change to the pod template, which triggers a rollout. Apply it, then change `PODINFO_UI_COLOR` (try `#c0392b`), apply again, and watch it roll out by itself.

Leftover: the old `podinfo-config` (without hash) is still in the cluster, because `kubectl apply` never deletes anything. Check with `kubectl get configmaps`, then delete it by hand. On AKS, Flux has `prune: true` and deletes objects you remove from git.

### 2. Secret (5 min)

`API_KEY` on http://localhost:9898/env comes from the Secret created by the kind overlay's `secretGenerator`.

```sh
kubectl get secrets
kubectl get secret <demo-secret-name> -o yaml        # look at data.API_KEY
kubectl get secret <demo-secret-name> -o go-template='{{.data.API_KEY | base64decode}}'
```

Anyone who can read a Secret can read its value. Base64 is encoding, not encryption. That's why the AKS overlay keeps the value in Key Vault, not in git.

### 3. Probes (10 min)

podinfo has two health endpoints, and the Deployment checks both:

| Probe | Endpoint | When it fails |
|---|---|---|
| readiness | `/readyz` | pod is removed from the Service, **not** restarted |
| liveness | `/healthz` | container is **restarted** |

**Readiness.** Make one pod report "not ready" (podinfo has an endpoint for that):

```sh
kubectl get pods
kubectl exec <pod-name> -- wget -qO- --post-data=x http://localhost:9898/readyz/disable
kubectl get pods                      # READY 0/1 for that pod, RESTARTS unchanged
kubectl describe endpointslices -l kubernetes.io/service-name=podinfo   # that pod: Ready false
```

The pod keeps running, but gets no traffic through the Service. Turn it back on:

```sh
kubectl exec <pod-name> -- wget -qO- --post-data=x http://localhost:9898/readyz/enable
```

**Liveness.** Add `- --unhealthy` to the `args` in `base/deployment.yaml`. With this flag, podinfo's `/healthz` never reports healthy. Apply and watch:

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl get pods -w                   # RESTARTS goes up, then CrashLoopBackOff
kubectl describe pod <pod-name>       # Events: "Liveness probe failed", "will be restarted"
```

Be patient: the new pods first look perfectly fine (`1/1 Running`, 0 restarts). Readiness still passes, so the rollout even completes. The first restart comes after about 35 seconds: the 5-second `initialDelaySeconds`, then 3 failed checks 10 seconds apart (`failureThreshold` defaults to 3). After that the pod cycles: start, look healthy, get killed. kubectl shows `CrashLoopBackOff`, and the wait between restarts doubles each time (up to 5 minutes).

That's why liveness checks are dangerous when they're wrong: an app that works fine (readiness passes, it serves traffic) gets killed over and over.

Remove `--unhealthy` again and apply.

**Checkpoint:** you can explain why a failing readiness probe is harmless to the pod, and a failing liveness probe isn't.

### 4. Break-fix (25 min)

The break script breaks your running podinfo without telling you how:

```sh
scripts/break.sh kind                 # bash
```

```powershell
.\scripts\break.ps1 kind              # PowerShell
```

Find out what's wrong, using only these:

| Command | Shows |
|---|---|
| `kubectl get pods` | STATUS, READY, RESTARTS |
| `kubectl describe pod <pod>` | Events, `Last State`, `Reason`, `Exit Code` |
| `kubectl get events --sort-by=.lastTimestamp` | everything that happened recently |
| `kubectl logs <pod>` / `kubectl logs <pod> --previous` | output of the current / the crashed container |
| `kubectl rollout status deployment podinfo` | whether a rollout is stuck |
| `kubectl get service` / `kubectl describe service podinfo` | the Service's `Selector`, and its `Endpoints`: the pods it actually found |
| `kubectl get pods --show-labels` | the pods' labels, to compare with the Service's selector |
| `kubectl describe endpointslices -l kubernetes.io/service-name=podinfo` | which pods the Service sends traffic to, and whether they're ready |
| `kubectl exec -it <pod> -- sh` | a shell inside the container |

When you know the cause, say it out loud to your neighbour, then fix it by applying your folder again:

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl get pods                      # all Ready again
```

Then run the break script again. There are 5 scenarios. Stuck for more than 5 minutes? `scripts/break.sh hint <number>`.

Notice that in most scenarios the app **keeps working**. `maxUnavailable: 0` keeps the old pods until new ones are Ready, so a broken rollout just gets stuck. That's the rolling update protecting you.

### 5. Commit and push (10 min)

Your folder is now different from what's in git. Push it:

```sh
git status
git add "participants/$NAME"
git commit -m "lab 2 ($NAME)"
git pull --rebase
git push
```

Ten people push to the same branch. If your push is rejected, someone pushed first: run `git pull --rebase` and push again. Only ever change files in your own folder, and the rebase never conflicts.

Open the repo on GitHub → **Actions** → **Publish participants**, and find the job named after you. Open the step *Validate manifests* → *Rendered overlays/aks (what Flux applies)*. It's empty: everything in your AKS overlay is still commented out. Your folder is now published to ACR, and nothing reaches AKS until Lab 3.

## Stretch task

- Crash podinfo on purpose and read why it died:

  ```sh
  kubectl exec <pod-name> -- wget -qO- http://localhost:9898/panic
  kubectl get pods                      # RESTARTS went up
  kubectl logs <pod-name> --previous    # "Panic command received"
  ```

- Debug a running pod with a temporary container that has more tools:

  ```sh
  kubectl debug -it <pod-name> --image=busybox:1.37.0 --target=podinfo
  ```

## Solution

[`labs/solutions/lab-2/`](solutions/lab-2/): your folder as it should look after this lab.
