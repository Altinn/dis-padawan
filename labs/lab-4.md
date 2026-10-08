# Lab 4 — Autoscaling with HPA

**Time:** 45 min · **Where:** AKS (`product-dis-training`), via git

## Goal

Make podinfo scale on CPU load, and see why the Deployment must stop setting `replicas` once a HorizontalPodAutoscaler (HPA) owns it.

## Before you start

- Lab 3 is done: your app answers on `https://dis-training-<name>.at22.dis-core.altinn.cloud`.
- Set `NAME` in every terminal, and check `kubectl config current-context` is AKS. You'll want three terminals.
- `hey` is installed (`hey -h`).

## Steps

### 1. Add an HPA (10 min)

Create `participants/<name>/overlays/aks/hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: podinfo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: podinfo
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
```

Add `- hpa.yaml` to `resources` in `overlays/aks/kustomization.yaml`. Render and check the `scaleTargetRef`: Kustomize knows HPAs and adds your prefix there by itself.

```sh
kubectl kustomize "participants/$NAME/overlays/aks"
```

"50% utilization" means 50% of the CPU **request** (50m in `base/deployment.yaml`), so 25m per pod. That's low on purpose, so a laptop can generate enough load.

Commit, `git pull --rebase`, push. When Flux has applied it:

```sh
kubectl get hpa "$NAME-podinfo"             # TARGETS cpu: 1%/50% (<unknown> for the first minute)
kubectl top pods -l "owner=$NAME"
```

### 2. Load it, and watch the fight (15 min)

Terminal 2 and 3, watch:

```sh
kubectl get hpa "$NAME-podinfo" -w
```

```sh
kubectl get deployment "$NAME-podinfo" -w
```

Terminal 1, generate load for 5 minutes:

```sh
hey -z 5m -c 20 "https://dis-training-$NAME.at22.dis-core.altinn.cloud/"
```

Within a minute or two the HPA scales up towards 5. Keep watching the Deployment. Within 2 minutes it **drops back to 3**, then the HPA scales it up again, and so on.

Two controllers disagree about `replicas`:

- The HPA sets it based on CPU.
- Flux sets it back to what's in git (`replicas: 3` in your base) every 2 minutes, because it corrects drift.

**Checkpoint:** you can explain who sets `replicas`, and why they fight.

### 3. Let the HPA own replicas (10 min)

Remove `replicas` from the Deployment **on AKS only**: kind has no HPA and still needs it. Add a patch to `overlays/aks/kustomization.yaml`:

```yaml
patches:
  - target:
      kind: Deployment
      name: podinfo
    patch: |-
      - op: remove
        path: /spec/replicas
```

Render: the Deployment has no `replicas` line any more. On kind, `kubectl kustomize "participants/$NAME/overlays/kind"` still has it. Push, and once Flux has applied it, load again:

```sh
hey -z 3m -c 20 "https://dis-training-$NAME.at22.dis-core.altinn.cloud/"
```

Now the replica count follows the load and stays there. When `hey` stops, the HPA scales down again, but only after 5 minutes. It waits that long by default, so a short dip in load doesn't remove pods you'll need again a moment later.

**Checkpoint:** the Deployment scales to 5 under load and back to 1 afterwards, and Flux no longer interferes.

## Stretch task

- **Faster scale-down.** Add to the HPA's `spec`, push, and load again:

  ```yaml
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
  ```

- **Load without hey.** Add `--stress-cpu=1` to podinfo's args with a second patch on AKS, so every pod burns CPU by itself. Where does the HPA end up, and why does it never come down? Remove it afterwards.
- `kubectl describe hpa "$NAME-podinfo"`: read the events. Every scaling decision is explained there.

## Solution

[`labs/solutions/lab-4/`](solutions/lab-4/): your folder as it should look after this lab (without the stretch tasks).
