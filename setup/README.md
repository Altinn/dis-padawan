# Setup (do this before the training day)

Do the setup on the network you normally use to reach AKS. On the day you need kind and AKS at the same time, so check that both work together.

Pinned versions and training settings live in [`config.env`](config.env). Both the bash and the PowerShell scripts read it.

## 1. Podman

We use Podman as the container runtime. Install Podman (https://podman.io/docs/installation) or Podman Desktop (https://podman-desktop.io). On Windows, enable WSL2 first (`wsl --install`, then reboot).

kind needs a Podman machine with at least 4 GB RAM. On Windows the machine runs in WSL2, which ignores `--memory`. There, set `memory=4GB` under `[wsl2]` in `%USERPROFILE%\.wslconfig` and run `wsl --shutdown`.

```sh
podman machine init --memory 4096 --cpus 2
podman machine start
```

Tell kind to use Podman permanently:

```sh
echo 'export KIND_EXPERIMENTAL_PROVIDER=podman' >> ~/.zshrc        # macOS, then open a new terminal
```

```powershell
[Environment]::SetEnvironmentVariable('KIND_EXPERIMENTAL_PROVIDER', 'podman', 'User')   # Windows, then open a new terminal
```

## 2. CLI tools

Install these with your usual package manager (Homebrew, winget, Chocolatey, …) or from the official pages:

| Tool | Required | Install docs |
|---|---|---|
| git | yes | https://git-scm.com/downloads |
| kubectl | yes | https://kubernetes.io/docs/tasks/tools/ |
| kind | yes | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| az CLI | yes | https://learn.microsoft.com/cli/azure/install-azure-cli |
| kubelogin | yes (kubectl calls it to sign in to AKS) | https://azure.github.io/kubelogin/install.html |
| flux | optional (read-only `flux get`) | https://fluxcd.io/flux/installation/#install-the-flux-cli |
| hey | optional (load generator, Lab 4) | https://github.com/rakyll/hey#installation |

`az aks install-cli` installs both kubectl and kubelogin.

### Optional: install scripts

As a shortcut, the install scripts install whatever is **missing** from your PATH. Tools you already have are kept as they are, whatever their version. Missing kind, kubectl, kubelogin and flux binaries are installed in your user bin folder at the versions pinned in `config.env`. The az CLI is installed with Homebrew (macOS) or winget (Windows). hey comes from Homebrew on macOS and is downloaded directly on Windows.

**macOS**

```sh
./setup/install-macos.sh          # installs into ~/.local/bin
```

**Windows (PowerShell)**

```powershell
powershell -ExecutionPolicy Bypass -File .\setup\install-windows.ps1   # installs into %USERPROFILE%\bin
```

Then open a new terminal. If `verify` warns that a version differs from the pinned one, that's usually fine. The exception is kubectl: it must be within one minor version of the AKS cluster (currently `<aks-kubernetes-version>`).

## 3. Connect to AKS

Run `az login`, then the `az aks get-credentials` command from the trainer's invitation email. It creates the kube context `dis-core-at22-aks`. Then check:

```sh
kubectl --context dis-core-at22-aks get pods -n product-dis-padawan
```

The command uses `--public-fqdn` because the cluster is private. Copy it as it is.

`kubelogin` must be on your PATH: kubectl calls it to get an Entra ID token. The first kubectl command asks you to sign in with a device code in the browser. After that the token is cached.

## 4. Verify

```sh
./setup/verify.sh                 # macOS
```

```powershell
.\setup\verify.ps1                # Windows
```

The verify script only checks that everything is ready; it doesn't create anything. You create the kind cluster yourself in Lab 1. It checks your tools, that Podman is running with at least 4 GB memory, and that `KIND_EXPERIMENTAL_PROVIDER=podman` is set. It pulls the kind node image into Podman, so `kind create cluster` in Lab 1 starts fast. It also pulls the podinfo image, but only to check that you can reach the registry: the kind node has its own image store and pulls podinfo again in Lab 1. It also checks that the AKS API is reachable and that you have kubectl access to the training namespace. Use `--skip-aks` / `-SkipAks` to run only the local checks.

**If any check fails, send the full output to the trainer before the training day.**

## Troubleshooting

| Symptom | Likely cause | Try |
|---|---|---|
| `kind create cluster` hangs or fails at "Starting control-plane" | Not enough Podman machine memory | macOS: `podman machine stop; podman machine set --memory 4096; podman machine start`. Windows (WSL2): set `memory=4GB` under `[wsl2]` in `%USERPROFILE%\.wslconfig`, then `wsl --shutdown` and `podman machine start` |
| Image pulls in kind are slow or time out, but work on the host | The Podman machine picked up a stale network/DNS config | `podman machine stop; podman machine start` |
| AKS API times out (`dial tcp ... i/o timeout`) | No network access to the private cluster from this machine | Check that you can reach your other AKS clusters; otherwise ask the trainer |
| Server URL in kubeconfig contains `privatelink` | Credentials fetched without `--public-fqdn` | Re-run the `az aks get-credentials` command from the invitation email |
| `az keyvault secret set` fails with `Forbidden` (Lab 3) | Not in the training Entra group, or the role assignment hasn't propagated yet | Wait a few minutes; otherwise send the trainer the error message |
