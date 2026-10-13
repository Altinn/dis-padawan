# Lab 1 — kind basics: apply -k, scale, roll out, roll back

**Time:** 60 min · **Where:** your kind cluster

## Goal

Run podinfo from your own folder and understand how Deployment → ReplicaSet → Pod → Service fit together.

## Before you start

Open a terminal in the root of this repo and set your name once per terminal. Every command below uses it, and works the same in bash and PowerShell.

```sh
NAME=alice              # bash (macOS)
```

```powershell
$NAME = "alice"         # PowerShell (Windows)
```

When a command blocks (port-forward, `-w` watches), open a second terminal and set `NAME` there too.

## Steps

### 1. Create your kind cluster (5 min)

kind ("Kubernetes in Docker") runs a whole Kubernetes cluster as a container in Podman. The cluster config is in [`setup/kind-config.yaml`](../setup/kind-config.yaml): one node, with a pinned Kubernetes version.

```sh
kind create cluster --config setup/kind-config.yaml
```

It takes a minute or two. kind adds a context `kind-k8s-training` to your kubeconfig and switches to it. Make the training namespace your default, so you don't need `-n` on every command:

```sh
kubectl config set-context --current --namespace product-dis-padawan
```

Check that the cluster works:

```sh
kubectl config current-context        # kind-k8s-training
kubectl get nodes                     # one node, STATUS Ready
kubectl get pods -A                   # the system pods that run Kubernetes itself
kubectl get pods                      # "No resources found in product-dis-padawan namespace."
podman ps                             # the "node" is just a container
```

`-A` (`--all-namespaces`) lists pods in every namespace: the system pods live in `kube-system` and `local-path-storage`. Without it, kubectl only looks in your default namespace, `product-dis-padawan`, and that's still empty. It doesn't even exist yet: your first `apply` in the next step creates it.

If `kind create cluster` fails, check that `KIND_EXPERIMENTAL_PROVIDER` is `podman`, then see the troubleshooting table in [setup/README.md](../setup/README.md#troubleshooting).

### 2. Render, then apply (10 min)

Look at your folder:

```
participants/<name>/
  base/              # what's the same everywhere: Deployment, Service, ConfigMap
  overlays/kind/     # what's specific to kind: the namespace, and the Secret
  overlays/aks/      # what's specific to AKS (Lab 3)
```

Open `base/kustomization.yaml`, `base/deployment.yaml` and `overlays/kind/kustomization.yaml`. Then render the kind overlay. This prints exactly what would be sent to the cluster, without sending it:

```sh
kubectl kustomize "participants/$NAME/overlays/kind"
```

Find these in the output:

- `namespace: product-dis-padawan` on every object: the overlay added it.
- A `Secret` named `demo-secret-<hash>`, and the Deployment's `secretRef` pointing at that exact name. The overlay's `secretGenerator` created it, and Kustomize rewrote the reference.
- `app.kubernetes.io/name: podinfo` in the Service selector **and** the pod labels: the base's `labels` added both.

Now apply it:

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl get pods -w                   # wait until both pods are 1/1 Running, then Ctrl+C
```

`apply -k` is "render, then apply". In the afternoon, Flux does exactly this for you on AKS.

### 3. Explore (10 min)

```sh
kubectl get deployments,replicasets,pods -o wide
kubectl get pods --show-labels
kubectl describe deployment podinfo
```

Pick one pod name from `kubectl get pods` and follow who owns whom:

```sh
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
kubectl get replicaset <replicaset-name> -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
```

**Checkpoint:** you can explain why the pod names look like `podinfo-<replicaset-hash>-<random>`.

### 4. Reach it (10 min)

The Service gives the pods one stable name and IP inside the cluster. Look at it first:

```sh
kubectl get service podinfo           # TYPE ClusterIP, PORT(S) 9898/TCP
kubectl describe service podinfo      # Selector, Port, TargetPort, Endpoints
```

Where does 9898 come from? Follow it through the files:

| Where | Setting | Meaning |
|---|---|---|
| `base/deployment.yaml` | `args: --port=9898` and `containerPort: 9898` named `http` | podinfo listens on 9898 (its default) |
| `base/service.yaml` | `port: 9898`, `targetPort: http` | the Service listens on 9898 and forwards to the container port named `http` |
| `describe service` | `Endpoints: 10.244.x.x:9898, …` | the pod IPs the Selector matched, on that port |

A `ClusterIP` Service is only reachable inside the cluster. From your laptop you go through a port-forward (second terminal; it blocks):

```sh
kubectl port-forward svc/podinfo 9898:9898
```

The format is `<port on your laptop>:<port on the Service>`. Using 9898 on both sides is just convenient. `8080:9898` works as well, and then you open http://localhost:8080 instead.

Open http://localhost:9898 in a browser. Then try:

- http://localhost:9898/version
- http://localhost:9898/env: find `PODINFO_UI_MESSAGE` (from the ConfigMap) and `API_KEY` (from the Secret).

```sh
curl localhost:9898/version           # bash
```

```powershell
curl.exe localhost:9898/version       # PowerShell: plain "curl" is Invoke-WebRequest in Windows PowerShell
```

### 5. Scale (10 min)

Scale by hand and watch:

```sh
kubectl scale deployment podinfo --replicas=4
kubectl get pods
```

Now apply your folder again:

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl get pods
```

You're back at 2. Your files say `replicas: 2`, and applying them wins. With GitOps on AKS, Flux does this re-apply every few minutes, so **a change that isn't in git doesn't last**.

Do it properly: set `replicas: 3` in `participants/<name>/base/deployment.yaml`, then apply again and check that you get 3 pods.

### 6. Rolling update and rollback (15 min)

In `base/deployment.yaml`, change the image tag from `6.15.0` to `6.14.1`. Apply, and watch the rollout in your second terminal (stop the port-forward first):

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl rollout status deployment podinfo -w
kubectl get replicasets                 # a new ReplicaSet scaled up, the old one scaled to 0
```

The Deployment uses `maxUnavailable: 0` and `maxSurge: 1`: it starts one new pod, waits until it's Ready, removes one old pod, and so on. The app never has fewer than 3 Ready pods.

Roll back with kubectl:

```sh
kubectl rollout history deployment podinfo
kubectl rollout undo deployment podinfo
kubectl get deployment podinfo -o jsonpath='{.spec.template.spec.containers[0].image}'
```

You're on 6.15.0 again. Now apply your folder once more:

```sh
kubectl apply -k "participants/$NAME/overlays/kind"
kubectl get deployment podinfo -o jsonpath='{.spec.template.spec.containers[0].image}'
```

6.14.1 is back, because your files still say so. `rollout undo` is an emergency button. **In GitOps, a rollback is a commit**: set the tag back to `6.15.0` in `base/deployment.yaml` and apply.

**Checkpoint:** 3 pods on `6.15.0`, and your files say the same.

## Stretch task

- Delete a pod (`kubectl delete pod <pod-name>`) and watch the ReplicaSet create a new one within seconds.
- Change `maxSurge` / `maxUnavailable` in the Deployment (e.g. `maxSurge: 3`), change the image tag, and watch how differently the rollout behaves.
- Start the port-forward to `svc/podinfo`, reload http://localhost:9898 a few times, and look at the hostname podinfo shows. It never changes: `port-forward` to a Service picks **one** pod and sticks to it. It's a debugging tool, not load balancing.

## Clean up (end of the day, or to start over)

```sh
kind delete cluster --name k8s-training
```

## Solution

[`labs/solutions/lab-1/`](solutions/lab-1/): your folder as it should look after this lab.
