# infra-deployments

## Konflux Community Deployment via ArgoCD 
```console
./deploy-argocd.sh <ArgoCD server> <production/staging>
```

## Accessing the Konflux Console
```console
kubectl port-forward -n konflux-ui svc/proxy 9443:9443 
```