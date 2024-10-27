#!/bin/bash -e
set -ex
# Deploy Applications to ArgoCD on EKS Cluster

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

main() {
    verify_permissions || exit $?
    login_argocd "$@"
    verify_pvc_binding
    deploy_apps
}

verify_permissions() {
    if [ "$(kubectl auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
        echo
        echo "[ERROR] User '$(oc whoami)' does not have the required 'cluster-admin' role." 1>&2
        echo "Log into the cluster with a user with the required privileges (e.g. kubeadmin) and retry."
        return 1
    fi
}

login_argocd() {
    if [ -z "$1" ]; then
        echo "No environment provided"
        exit 1
    fi

    ARGOCD_SERVER=$(echo "$1"|tr '[:upper:]' '[:lower:]')
    argocd login $ARGOCD_SERVER --sso
}

verify_pvc_binding(){
    local pvc_resources="${ROOT}/argo-cd-apps/dependencies/pre-deployment-pvc-binding"
    echo "Creating PVC from '$pvc_resources' using the cluster's default storage class"
    kubectl apply -k "$pvc_resources"
    echo "PVC binding successfull"
}

deploy_tekton_secret() {
    if ! kubectl get secret tekton-results-postgres -n tekton-pipelines; then
        local db_password
        db_password="$(openssl rand -base64 20)"
        kubectl create secret generic tekton-results-postgres \
            --namespace="tekton-pipelines" \
            --from-literal=POSTGRES_USER=postgres \
            --from-literal=POSTGRES_PASSWORD="$db_password"
    fi
}

deploy_keycloak_secret() {
    if ! kubectl get secret keycloak-db-secret -n keycloak; then
        local db_password
        db_password="$(openssl rand -base64 20)"
        kubectl create secret generic keycloak-db-secret \
            --namespace=keycloak \
            --from-literal=POSTGRES_USER=postgres \
            --from-literal=POSTGRES_PASSWORD="$db_password"
    fi
}

check_namespace() {
    kubectl get namespace "$1" &>/dev/null
    return $?
}

deploy_apps() {
    echo "Deploying applications"
    kubectl apply -k "${ROOT}/argo-cd-apps/app-of-app-sets/staging"
    while true; do
        if check_namespace "tekton-pipelines" && check_namespace "keycloak"; then
            deploy_tekton_secret
            deploy_keycloak_secret
            break
        else
            echo -n .
            sleep 1
        fi
    done
    echo "Applications deployed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
