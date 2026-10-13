# Publish workflows

Same pattern as `Altinn/dialogporten-manifests` (`publish-flux-artifacts.yml`): artifacts are pushed with `Altinn/altinn-platform/actions/flux/build-push-image`, tagged with the short commit SHA plus a moving tag.

> **Push triggers are currently commented out** until the repo has moved to the Altinn org and secrets, runners and ACR access are in place. Only manual runs (*Run workflow*) work. Uncomment the `push:` blocks before the training: the labs rely on them.

| Workflow | Trigger | Pushes | Tag | Applied by |
|---|---|---|---|---|
| [`publish-syncroot.yml`](publish-syncroot.yml) | push to `main` touching `flux/syncroot/**`, or manual | `./flux/syncroot` → `altinncr.azurecr.io/dis-padawan/syncroot` | `at22` | Platform syncroot → path `./at22` |
| [`publish-participants.yml`](publish-participants.yml) | push to `main` touching `participants/**` (not `_template/`), or manual (publishes everyone) | `./participants/<name>` → `altinncr.azurecr.io/dis-padawan/<name>` | `main` | OCIRepository + Flux Kustomization `<name>` from the syncroot → path `./overlays/aks` |

Flux chain: platform → `dis-padawan/syncroot:at22` → `flux/syncroot/base/<name>.yaml` → `dis-padawan/<name>:main` → `participants/<name>/overlays/aks`.

## Behaviour

- **Only changed participants are published**: the diff of the push decides which `participants/<name>/` folders get a job (one matrix job each). Deleted folders (cleanup) are skipped.
- **Validation**: both workflows render with `kustomize build` before pushing. The participant job prints the rendered AKS overlay in the log, so participants can see exactly what Flux will apply. The syncroot job fails if an entry has no participant folder or isn't listed in `base/kustomization.yaml`.
- **Concurrency**: one publish at a time per participant; a newer queued run replaces an older one.
- **Runner**: `self-hosted`, like the platform example. kustomize is installed by [`.github/actions/setup-kustomize`](../actions/setup-kustomize/action.yaml) (checksum-verified).

## Needs from the trainer

- Repository secrets `DIS_SYNCROOT_AZURE_SUBSCRIPTION_ID`, `DIS_SYNCROOT_AZURE_CLIENT_ID`, `DIS_SYNCROOT_AZURE_TENANT_ID`. The app needs push access to `altinncr.azurecr.io/dis-padawan/*` and a federated credential for this repo's `main` branch.
- Self-hosted runners available to this repository.

## Not enforced

Nothing stops a participant from pushing changes to someone else's folder: CODEOWNERS only applies to pull requests. The training relies on "only touch your own folder". Use branch protection with PRs if that's not good enough.

The tag `main` is a moving tag: a training shortcut. Mention immutable tags/digests in the wrap-up.
