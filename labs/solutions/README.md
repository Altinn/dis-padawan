# Solutions

`lab-N/` is a participant folder as it should look **after** lab N. Compare it with yours:

```sh
diff -r labs/solutions/lab-2 "participants/$NAME"
```

```powershell
git diff --no-index labs/solutions/lab-2 "participants/$NAME"
```

Files in `overlays/aks/` contain `__NAME__` where your folder has your name: that difference is expected. If you copy a file from here, replace `__NAME__` with your name.

| Folder | What changed compared to the previous lab |
|---|---|
| `lab-1/` | `replicas: 3` in `base/deployment.yaml` (image back on 6.15.0) |
| `lab-2/` | `base/configmap.yaml` replaced by a `configMapGenerator` in `base/kustomization.yaml` |
| `lab-3/` | all resources enabled in `overlays/aks/kustomization.yaml`; AKS-only UI message via `configMapGenerator` `behavior: merge` |
| `lab-4/` | `overlays/aks/hpa.yaml`; patch that removes `replicas` from the Deployment on AKS |
