# Labs

| Lab | Where | Topic | Guide |
|---|---|---|---|
| 1 | kind | create the cluster, `apply -k`, scale, rolling update, rollback, Service + port-forward | [lab-1.md](lab-1.md) |
| 2 | kind | ConfigMap, Secret, probes, break-fix, commit + push | [lab-2.md](lab-2.md) |
| 3 | AKS | identity + Key Vault, secret, ExternalSecret, HTTPRoute, git push → workflow → Flux | [lab-3.md](lab-3.md) |
| 4 | AKS | HPA + load generator | [lab-4.md](lab-4.md) |

Every lab has a goal, steps (bash **and** PowerShell), and a stretch task. Stuck for more than 5 minutes? Compare your folder with [`labs/solutions/lab-<n>/`](solutions/).

Optional (15:15–15:45, if time allows): break-fix on AKS with `scripts/break.sh aks <name>`. It suspends your Flux Kustomization first (otherwise Flux undoes the break within 2 minutes) and adds AKS-only scenarios: ExternalSecret failing, HTTPRoute not attached. Fix with `flux resume kustomization <name> -n product-dis-training`.
