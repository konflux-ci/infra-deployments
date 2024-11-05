# infra-deployments

## Konflux Community Deployment via ArgoCD
```bash
./deploy-argocd-apps.sh <production/staging>
```

## Accessing the Konflux Console
```bash
kubectl port-forward -n konflux-ui svc/proxy 9443:9443 
```

## Setting up a development environment using kind

### Installing Software Dependencies
Verify that the applications below are installed on the host machine:

* [Kind and kubectl](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
  along with `podman` or `docker`

### Bootstrapping the development cluster
Clone this repository:

 ```bash
git clone https://github.com/konflux-ci/infra-deployments
cd infra-deployments
```

**Note:** It is recommended that you increase the `inotify` resource limits in order to
avoid issues related to
[too many open files](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files). 
To increase the limits temporarily, run the following commands:

```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

From the root of this repository, run the setup scripts:

1. Create a cluster

```bash
kind create cluster --name dev --config kind-config.yaml
```

**Note:** When using Podman, it is recommended that you increase the PID limit on the
container running the cluster, as the default might not be enough when the cluster
becomes busy:

```bash
podman update --pids-limit 4096 dev-control-plane
```

**Note:** If pods still fail to start due to missing resources, you may need to reserve
additional resources to the Kind cluster. Edit [kind-config.yaml](./kind-config.yaml)
and modify the `system-reserved` line under `kubeletExtraArgs`:

```yaml
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        system-reserved: memory=12Gi
```

2. Create argocd namespace in the cluster:
```bash
kubectl create namespace argocd
```

3. Deploy ArgoCD:
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

4. Run the deployment script:
```bash
./deploy-argocd-apps.sh staging
```
It might take several minutes for all the components to sync and become healthy.
To monitor the components, we need to extract ArgoCD server's secret, port-forward to ArgoCD 
server and navigate to the ArgoCD URL:

* Obtain ArgoCD server's password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

* Port forward the ArgoCD Server service:

```bash
kubectl port-forward -n argocd service/argocd-server 8443:443
```

ArgoCD UI is now available at https://localhost:8443

```console
User: admin
Password: <obtained previously from the cluster>
```

Once the cluster is up and running, we are able to view Konflux UI at https://localhost:9443
