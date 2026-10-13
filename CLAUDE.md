# Kubernetes & AKS Training — Project Context

This repo contains everything for a 1-day (+ optional ½ day) hands-on Kubernetes/AKS training for internal developers and architects. Participants commit their own work here, and pre-made GitHub workflows deploy it. Read this file fully before doing anything.

## Working style

- The owner is a senior cloud architect / platform engineer. Be concise and precise.
- If an assumption or decision looks wrong, say so directly. No sugarcoating.
- Ask before inventing anything platform-specific. Use `<placeholders>` until confirmed.
- The owner fills in Entra ID group IDs himself — leave `<training-group-object-id>` placeholders.
- Pin all tool and image versions. Verify Kustomize output with `kubectl kustomize` before calling anything done.

## Audience & constraints

- Under 10 attendees, developers and architects, same content for both.
- Comfortable with Docker, no Kubernetes experience.
- OS mix: **Windows and macOS**.
- Afterwards they deploy to an AKS platform the owner runs: **GitHub workflows** build and push **OCI artifacts** to ACR, **Flux** (AKS extension) deploys them, manifests packaged with **Kustomize**.
- Ingress: **Traefik, Gateway API only** (HTTPRoute; no IngressRoute, no Ingress).
- Secrets: **External Secrets Operator** (Azure Key Vault, workload identity).
- Observability: **OpenTelemetry collector** (already deployed) + Azure Managed Prometheus/Grafana.
- Participants are **admin in the training namespace** (they can break things on AKS too; Flux undoes manual changes within its 2m interval unless their Kustomization is suspended). Side effect: they can also change other participants' resources; the training relies on discipline.
- **This repo will be public.** Never commit subscription, resource group or cluster names, tenant/object IDs, or how the private network is reached. Those go in the trainer's invitation email.
- AKS clusters are **private**, reached over the participants' existing network setup (keep that out of the training material: no setup steps, checks or troubleshooting for it). Participants get the `az aks get-credentials … --public-fqdn --overwrite-existing` command from the invitation email; the resulting kube context is `dis-core-at22-aks` (the only cluster identifier in the repo).

## Platform facts

| Item | Value |
|---|---|
| Flux distribution (cluster) | flux-v2.8.8 (AKS extension) |
| ESO | 2.11.0 → `external-secrets.io/v1` |
| ACR | `altinncr.azurecr.io` |
| Environment | `at22` |
| Namespace | `product-dis-padawan` (platform convention `product-<team>`) |
| Deploy path | `git push` → pre-made GitHub workflow → OCI artifact in ACR → Flux |
| Syncroot | `flux/syncroot/` (base + `at22` overlay) pushed to `altinncr.azurecr.io/dis-padawan/syncroot:at22`; the platform applies `./at22`. Pattern: `Altinn/dialogporten-manifests` `flux/syncroot` |
| Participant artifacts | `participants/<name>/` → `altinncr.azurecr.io/dis-padawan/<name>:main`; syncroot holds OCIRepository + Flux Kustomization `<name>` (`path: ./overlays/aks`, `prune: true`) per participant |
| Namespace, RBAC, syncroot Flux objects | **Existing platform setup**; the platform's syncroot Kustomization impersonates a namespaced SA. Reuse, don't reinvent |
| Key Vault | Per participant, `Vault` CR (dis-vault-operator); operator also creates the SecretStore |
| Identity | Per participant, `ApplicationIdentity` CR (dis-identity-operator): UAMI, federated credential, ServiceAccount |
| ResourceQuota / LimitRange | Owner adds them to the platform's namespace setup; not in this repo |
| Hostnames / TLS | Handled by platform; wildcard `*.at22.dis-core.altinn.cloud` → per person `dis-padawan-<name>.at22.dis-core.altinn.cloud` |
| Gateway parentRef | Gateway `traefik-gateway` in namespace `traefik` (no `sectionName`) |

## Core design decisions (agreed, don't relitigate without reason)

1. **Morning on kind, afternoon on AKS.** kind keeps the basics free of Flux, gateways, pipelines and private-cluster networking. Goal: on AKS by lunch.
2. **No gateway on kind.** Service + `kubectl port-forward` only. HTTPRoute first appears on AKS.
3. **`kubectl apply -k` from the first lab.** Attendees run by hand what Flux later does for them, so Flux isn't magic. Sequence: `apply -k` on kind → `kubectl kustomize` the AKS overlay locally → `git push` → workflow pushes artifact → Flux applies the same thing.
4. **HPA moves to AKS** (metrics-server is built in).
5. **Basic debugging stays in the morning** (logs, describe, events, exec; ImagePullBackOff, CrashLoopBackOff, failing probes, OOMKilled).
6. **One full app copy per participant**: `participants/<name>/`. Avoids a shared base that one person can break for everyone; workflow builds only the changed participant folder (paths filter).
7. **One shared namespace `product-dis-padawan` on AKS**, isolated per person by:
   - `namePrefix: <name>-`
   - `labels` with `includeSelectors: true` (prevents Service selectors silently routing to other people's pods)
   - one OCIRepository + Flux Kustomization per person, defined in the syncroot (`flux/syncroot/base/<name>.yaml`), `prune: true`
   - ResourceQuota + LimitRange from the platform namespace setup
   - per-person hostname `dis-padawan-<name>.at22.dis-core.altinn.cloud`
8. **Participants deploy their own ApplicationIdentity + Vault** and create secret `demo-api-key` in their own vault. No shared vault, no trainer-owned SecretStore.
9. **Cleanup** = remove the person from the syncroot (and their folder), push; Flux prunes their OCIRepository + Kustomization and everything it applied. Prune also removes their Vault + ApplicationIdentity (operators delete the Azure resources). Then delete their ACR repository (`scripts/cleanup.sh`, two phases).
10. **Demo app: podinfo** (confirmed).

## Schedule (draft)

Day 1, 08:30–16:00:

| Time | Block |
|---|---|
| 08:30–08:45 | Kickoff, goals, environment check (setup done beforehand) |
| 08:45–09:30 | Theory: Deployment/ReplicaSet/Pod, Service, ConfigMap, Secret, Namespace, requests/limits, probes, HPA, Gateway API (one diagram, max 45 min) |
| 09:30–10:30 | Lab 1 (kind): create the kind cluster (`kind create cluster --config setup/kind-config.yaml`), `apply -k` base + kind overlay, scale, rolling update, rollback, Service + port-forward |
| 10:45–11:45 | Lab 2 (kind): ConfigMap (plain first → pods don't restart → `configMapGenerator`), Secret (visible via `/env`), probes, break-fix via trainer break script. Commit and push their folder (`git pull --rebase` practice) |
| 11:45–12:30 | Lunch |
| 12:30–13:00 | Platform intro: AKS, workflow → ACR → Flux, ESO + Key Vault, Gateway API, what kubectl can/can't do here |
| 13:00–14:15 | Lab 3 (AKS): round 1 = enable identity + Key Vault in the AKS overlay and push **first** (Azure works while they continue); create secret in it; round 2 = enable base + ExternalSecret + HTTPRoute, render overlay locally, `git push`, follow workflow run + Flux reconcile, verify via hostname |
| 14:30–15:15 | Lab 4 (AKS): HPA + load generator |
| 15:15–15:45 | Buffer; optionally AKS break-fix with `scripts/break.sh aks <name>` (suspends their Flux Kustomization, adds ExternalSecret + HTTPRoute scenarios; fix = `flux resume`) |
| 15:45–16:00 | Wrap-up, next steps, where to get help |

Cut order if behind: HPA becomes a demo, then shorten theory. Never cut Lab 3.

Optional ½ day (observability & debugging, ~3.5h): podinfo traces via OTLP to the collector, podinfo metrics (Prometheus format) via the collector, Grafana exploration + simple alert, AKS failure scenarios (sync errors, ESO, workload identity, HPA not scaling, OOMKilled). Exact content depends on the trace backend (open question).

## Teaching goals (day 1)

Attendees can:
1. Explain how the core objects relate.
2. Run, scale, update and roll back an app on kind.
3. Diagnose the common pod failures.
4. Structure manifests as Kustomize base + overlays.
5. Deploy to AKS via git push → workflow → Flux, and know the limits of their kubectl access there.

Method: theory ≤20%, every lab has goal / steps / stretch task, a solved participant folder per lab in `labs/solutions/lab-N/` (on main, diff-able) so nobody is stuck >5 min, break-fix on kind via a break script. Lab outlines live in `labs/lab-N.md`.

## Target repo layout

```
.github/workflows/            # publish-syncroot.yml, publish-participants.yml (changed participants only)
flux/syncroot/                # syncroot artifact: base/<name>.yaml per participant + at22 overlay
participants/
  _template/                  # copied per participant by scripts/
    base/                     # deployment, service, configmap (podinfo)
    overlays/
      kind/                   # secretGenerator for demo-secret
      aks/                    # kustomization, externalsecret, httproute, kustomizeconfig
  <name>/                     # one per participant, generated from _template
setup/                        # kind config, install + verify scripts (PowerShell + bash)
labs/                         # lab guides (markdown)
scripts/                      # add-participant.sh (folder + syncroot entry), cleanup.sh
```

Artifact per participant contains `participants/<name>/`; Flux Kustomization `path: ./overlays/aks`. Workflow contract: `.github/workflows/README.md`.

## Demo app: podinfo

- Image: `ghcr.io/stefanprodan/podinfo:6.15.0`. AKS pulls `altinncr.azurecr.io/ghcr.io/stefanprodan/podinfo` (ACR pull-through cache, already set up; no import needed). kind can pull from ghcr.io directly.
- ConfigMap → `PODINFO_UI_MESSAGE`; Secret → `API_KEY` via `envFrom`; both visible on `/env`.
- Probes: `/healthz`, `/readyz`; `POST /readyz/disable` fails readiness on demand.
- Break-fix: wrong tag (ImagePullBackOff), `/panic` or bad args (CrashLoopBackOff), `--stress-memory` with low memory limit (OOMKilled).
- HPA: `--stress-cpu` or load generator against low CPU request.
- OpenTelemetry: podinfo exports **traces** via OTLP (service name flag + OTLP endpoint env). **Metrics stay Prometheus format on `/metrics`** — the collector must scrape them (Prometheus receiver) if metrics should flow through it. Confirm collector endpoint and how it discovers scrape targets.
- Verify all endpoints/flags/env vars against the pinned version before writing labs.

## Key design: participant AKS overlay

Source of truth is `participants/_template/overlays/aks/` (token `__NAME__`). Its `resources` start **all commented out**, so pushes during the kind labs deploy nothing to AKS; Lab 3 uncomments them in two rounds (identity + vault first, then base + ExternalSecret + HTTPRoute). Base Deployment references the secret as `demo-secret` (`envFrom.secretRef.name`); the kind overlay creates it with `secretGenerator`, the AKS overlay with an ExternalSecret of the same name.

**Each participant deploys their own identity and Key Vault** (nothing shared, no trainer-owned platform objects in this repo). Operators live in `Altinn/altinn-platform/services/`:
- `ApplicationIdentity` (`application.dis.altinn.cloud/v1alpha1`, dis-identity-operator): creates UAMI + federated credential + a ServiceAccount **named like the CR**, annotated with `azure.workload.identity/client-id`.
- `Vault` (`vault.dis.altinn.cloud/v1alpha1`, dis-vault-operator): `identityRef` → the ApplicationIdentity; `groupObjectId: <training-group-object-id>` gives participants secret access; `externalSecrets: true` makes the operator create SecretStore `<vault-name>-secret-store`. Azure name is computed (`status.azureName`, deterministic per namespace/name/env) → `purgeProtectionEnabled: false`, `softDeleteRetentionDays: 7` so a vault can be recreated.
- Participant creates the secret in their own vault: `az keyvault secret set --vault-name $(kubectl get vault <name>-podinfo -n product-dis-padawan -o jsonpath='{.status.azureName}') --name demo-api-key --value "<anything>"`.
- ExternalSecret `secretStoreRef.name` is written out as `__NAME__-podinfo-secret-store` (Kustomize can't derive the operator's suffix).

`kustomizeconfig.yaml` teaches Kustomize three references so `namePrefix` stays consistent: ExternalSecret → Deployment `envFrom.secretRef`, Service → HTTPRoute `backendRefs`, ApplicationIdentity → Vault `spec.identityRef.name`.

**Must verify** with `kubectl kustomize participants/alice/overlays/aks` (after `scripts/add-participant.sh alice` and uncommenting all resources):
- `alice-demo-secret` in both ExternalSecret and Deployment
- `alice-podinfo` in Service, HTTPRoute `backendRefs`, ApplicationIdentity, Vault and Vault `identityRef`
- ExternalSecret `secretStoreRef` = `alice-podinfo-secret-store`; Gateway `parentRefs` unprefixed

Gateway: `traefik-gateway` (namespace `traefik`), no `sectionName`; confirm its `allowedRoutes` admits namespace `product-dis-padawan`.

## Known gotchas to handle

- **Container runtime is Podman only** (no Docker Desktop, no Rancher Desktop; don't mention alternatives). kind needs `KIND_EXPERIMENTAL_PROVIDER=podman` and a Podman machine with ≥ 4 GB (rootless is fine). Windows needs WSL2.
- **Setup check only verifies readiness, it creates nothing**: tools, Podman running + ≥ 4 GB, `KIND_EXPERIMENTAL_PROVIDER=podman`, pre-pulls the kind node image (podinfo pull is only a registry check; kind's containerd pulls it again), verifies AKS API reachability (and that credentials use `--public-fqdn`), kubectl to AKS and `az keyvault` access.
- **Concurrent pushes**: several people pushing to the same branch → rejected pushes. Teach `git pull --rebase`. Participants only touch `participants/<name>/` (consider CODEOWNERS or a check in the workflow).
- **Workload identity**: federated credentials bind to the exact SA name/namespace. The SA comes from the ApplicationIdentity (same name); participants must not create or rename it by hand.
- **Key Vault creation takes minutes** the first time: Flux Kustomization `timeout: 5m`, ExternalSecret retries until the operator's SecretStore exists.
- **Managed Prometheus** (if scraped directly rather than via the collector) uses `azmonitoring.coreos.com/v1` PodMonitor/ServiceMonitor, not upstream CRDs.
- `latest`-style tags are a training shortcut if the workflow uses them; mention immutable tags/digests in wrap-up.
- PowerShell equivalents needed for all commands in lab guides.

## Prerequisites (participants)

git + GitHub access to this repo, kubectl, kind, Podman (machine with ≥ 4 GB), az CLI, kubelogin (AKS Entra auth), optional flux CLI (2.8.x, read-only use: `flux get`), a load generator (e.g. `hey`).

## Tasks (suggested order)

1. Scaffold repo layout above.
2. `participants/_template/` base (podinfo) + kind overlay; verify on a fresh kind cluster.
3. kind config + setup and verify scripts for Windows (PowerShell, WSL2) and macOS.
4. AKS overlay template + `kustomizeconfig.yaml`; verify rendered output.
5. ~~`platform/training/`~~ dropped: identity + vault are per participant, quota/LimitRange are platform setup.
6. `scripts/add-participant.sh` (folder + syncroot entry) and `scripts/cleanup.sh`.
7. Publish workflows: `.github/workflows/publish-syncroot.yml`, `publish-participants.yml` (changed participants only).
8. **Done (untested on a live cluster):** lab guides 1–4 in `labs/` (commands quote `"$NAME"` so one line works in bash and PowerShell; only variable assignment, base64 and `curl.exe` differ); solutions in `labs/solutions/lab-N/` (end states: L1 replicas 3, L2 configMapGenerator, L3 all AKS resources + `behavior: merge` message, L4 HPA + patch removing `replicas` on AKS); break script `scripts/break.sh` + `break.ps1` (written; participant-run on kind or AKS, hides the cause; scenarios 1–5 both, 6–7 AKS only).
9. Optional ½-day material: OTel traces + metrics, Grafana, failure scenarios.
10. Trainer prep checklist + dry-run checklist.

## Open questions

- Entra training group not created yet → `<training-group-object-id>` in `vault.yaml` (template + solutions)
- Confirm `traefik-gateway` admits HTTPRoutes from `product-dis-padawan` and serves `*.at22.dis-core.altinn.cloud`
- OTel: collector endpoint, how it scrapes Prometheus metrics, trace backend in Grafana
- Repo moves to the Altinn org later; then the `DIS_SYNCROOT_AZURE_*` secrets and self-hosted runners apply as in dialogporten-manifests. **Push triggers in both publish workflows are commented out until then**; re-enable them before the training (labs depend on them). Fill `<trainer-github-handle>` in CODEOWNERS