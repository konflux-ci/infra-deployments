#!/bin/bash -e
set -ex

if [ "$#" -ne 1 ] || ([ "$1" != "production" ] && [ "$1" != "staging" ] ); then
  echo "Usage: $0 <staging/production>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

main() {
    verify_permissions || exit $?
    verify_pvc_binding
    deploy_apps "$1"
}

verify_permissions() {
    if [ "$(kubectl auth can-i '*' '*' --all-namespaces)" != "yes" ]; then
        echo
        echo "[ERROR] User '$(oc whoami)' does not have the required 'cluster-admin' role." 1>&2
        echo "Log into the cluster with a user with the required privileges (e.g. kubeadmin) and retry."
        return 1
    fi
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
    environment=$(echo "$1")
    echo "Deploying applications"
    kubectl apply -k "${ROOT}/argo-cd-apps/app-of-app-sets/${environment}"
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
