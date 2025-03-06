#!/bin/bash -e
set -ex

if [ "$#" -ne 1 ] || ([ "$1" != "production" ] && [ "$1" != "staging" ] ); then
  echo "Usage: $0 <staging/production>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

main() {
    verify_permissions || exit $?
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

check_namespace() {
    kubectl get namespace "$1" &>/dev/null
    return $?
}

deploy_dex_secret() {
    if ! kubectl get secret oauth2-proxy-client-secret -n dex; then
        local client_secret
        client_secret="$(openssl rand -base64 20 | tr '+/' '-_' | tr -d '\n' | tr -d '=')"
        kubectl create secret generic oauth2-proxy-client-secret \
            --namespace=dex \
            --from-literal=client-secret="$client_secret"
        kubectl create secret generic oauth2-proxy-client-secret \
            --namespace=konflux-ui \
            --from-literal=client-secret="$client_secret"
    else
        kubectl delete secret --ignore-not-found=true oauth2-proxy-client-secret \
            --namespace=konflux-ui
        kubectl get secret oauth2-proxy-client-secret --namespace=dex \
            -o yaml | grep -v '^\s*namespace:\s' \
            | kubectl apply --namespace=konflux-ui -f -
    fi

    kubectl delete secret --ignore-not-found=true oauth2-proxy-cookie-secret \
        --namespace=konflux-ui
    local cookie_secret
    # The cookie secret needs to be 16, 24, or 32 bytes long.
    # kubectl is re-encoding the value of cookie_secret, so when it's being served
    # to oauth2-proxy, it's actually the 24 bytes string which was the output of
    # openssl's encoding.
    # Need to make sure this is consistent, or find a different approach.
    cookie_secret="$(openssl rand -base64 16)"
    kubectl create secret generic oauth2-proxy-cookie-secret \
        --namespace=konflux-ui \
        --from-literal=cookie-secret="$cookie_secret"

}

deploy_apps() {
    environment=$(echo "$1")
    echo "Deploying applications"
    kubectl apply -k "${ROOT}/argo-cd-apps/app-of-app-sets/${environment}"
    while true; do
        if check_namespace "tekton-pipelines" && check_namespace "dex" && check_namespace "konflux-ui"; then
            deploy_tekton_secret
            deploy_dex_secret
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
