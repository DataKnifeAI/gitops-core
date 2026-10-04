#!/bin/bash
#
# Create kubeconfig secret for cert-sync CronJob
#
# This script builds a kubeconfig with contexts rancher-manager, nprd-apps, poc-apps
# and prd-apps and stores it as secret 'cert-sync-kubeconfig' in the cert-manager
# namespace on rancher-manager. The CronJob mounts it as /kubeconfig/config.
#
# Every context talks to the cluster's kube-apiserver on :6443 directly with the RKE2
# admin client certificate, so cert-sync does not depend on Rancher, Rancher tokens or
# Rancher's (dynamiclistener) CA.
#
# Prerequisites:
#   - RKE2 admin (break-glass) kubeconfigs ${KUBECONFIG_DIR}/<cluster>-rke2.yaml for every
#     cluster (default KUBECONFIG_DIR=~/.kube). Fetch from /etc/rancher/rke2/rke2.yaml on a
#     server node and rewrite server to https://<cluster-dns>:6443; the endpoint must be in
#     the apiserver cert SANs and reachable from pods on rancher-manager.
#   - The secret is written with ${KUBECONFIG_DIR}/rancher-manager-rke2.yaml.
#
# Usage:
#   ./create-cert-sync-kubeconfig-secret.sh
#   KUBECONFIG_DIR=/path/to/dir ./create-cert-sync-kubeconfig-secret.sh
#
# The RKE2 admin client certs expire with the RKE2 certificates: re-fetch the
# <cluster>-rke2.yaml files and re-run this script after every RKE2 cert rotation.

set -euo pipefail

CLUSTERS=("rancher-manager" "nprd-apps" "poc-apps" "prd-apps")
KUBECONFIG_DIR="${KUBECONFIG_DIR:-${HOME}/.kube}"
SECRET_NAME="cert-sync-kubeconfig"
NAMESPACE="cert-manager"
MANAGER_KUBECONFIG="${KUBECONFIG_DIR}/rancher-manager-rke2.yaml"

for bin in kubectl jq; do
    if ! command -v "${bin}" &> /dev/null; then
        echo "❌ Error: ${bin} not found"
        exit 1
    fi
done

WORKDIR=$(mktemp -d)
chmod 700 "${WORKDIR}"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "📋 Building kubeconfig for cert-sync CronJob from ${KUBECONFIG_DIR}/<cluster>-rke2.yaml..."

parts=()
for cluster in "${CLUSTERS[@]}"; do
    src="${KUBECONFIG_DIR}/${cluster}-rke2.yaml"
    dst="${WORKDIR}/${cluster}.json"
    if [[ ! -f "${src}" ]]; then
        echo "❌ Error: ${src} not found"
        exit 1
    fi

    # Normalise names so the merged kubeconfig has one context per cluster, named as
    # the sync script expects
    kubectl --kubeconfig "${src}" config view --raw --minify -o json | \
        jq --arg n "${cluster}" '
            .clusters[0].name = $n
            | .users[0].name = ($n + "-admin")
            | .contexts[0].name = $n
            | .contexts[0].context.cluster = $n
            | .contexts[0].context.user = ($n + "-admin")
            | ."current-context" = $n' > "${dst}"

    server=$(kubectl --kubeconfig "${dst}" config view -o jsonpath='{.clusters[0].cluster.server}')
    if [[ "${server}" == *127.0.0.1* || "${server}" == *localhost* ]]; then
        echo "❌ Error: ${src} still points at ${server}; rewrite it to a reachable endpoint"
        exit 1
    fi
    printf '   %-16s %s ' "${cluster}" "${server}"
    if ! kubectl --kubeconfig "${dst}" --request-timeout=15s get --raw=/readyz >/dev/null; then
        echo "❌ unreachable or unauthorized"
        exit 1
    fi
    echo "✅"
    parts+=("${dst}")
done

MERGED="${WORKDIR}/config"
KUBECONFIG=$(IFS=:; echo "${parts[*]}") kubectl config view --raw --flatten > "${MERGED}"
kubectl --kubeconfig "${MERGED}" config use-context "${CLUSTERS[0]}" >/dev/null

echo ""
echo "🔐 Writing secret '${SECRET_NAME}' in namespace '${NAMESPACE}' on rancher-manager..."

# Server-side apply: client-side apply would copy the credentials into the
# kubectl.kubernetes.io/last-applied-configuration annotation
kubectl --kubeconfig "${MANAGER_KUBECONFIG}" create secret generic "${SECRET_NAME}" \
    --from-file=config="${MERGED}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | \
kubectl --kubeconfig "${MANAGER_KUBECONFIG}" apply --server-side --force-conflicts \
    --field-manager=create-cert-sync-kubeconfig-secret -f -

kubectl --kubeconfig "${MANAGER_KUBECONFIG}" annotate secret "${SECRET_NAME}" \
    --namespace="${NAMESPACE}" \
    kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true

kubectl --kubeconfig "${MANAGER_KUBECONFIG}" label secret "${SECRET_NAME}" \
    --namespace="${NAMESPACE}" \
    app=cert-manager \
    managed-by=gitops \
    purpose=cert-sync \
    --overwrite

echo ""
echo "✅ Secret '${SECRET_NAME}' created/updated with contexts: ${CLUSTERS[*]}"
echo "   Test it: kubectl -n ${NAMESPACE} create job --from=cronjob/cert-sync cert-sync-manual-\$(date +%s)"
