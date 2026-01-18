#!/bin/bash
#
# Create kubeconfig secret for cert-sync CronJob
#
# This script creates a Kubernetes secret containing a kubeconfig file
# that allows the cert-sync CronJob to access multiple clusters (rancher-manager,
# nprd-apps, poc-apps, prd-apps) for syncing TLS certificates.
#
# Prerequisites:
#   - kubectl configured with contexts: rancher-manager, nprd-apps, poc-apps, prd-apps
#   - Access to create secrets in cert-manager namespace on rancher-manager cluster
#
# Usage:
#   ./create-cert-sync-kubeconfig-secret.sh [rancher-manager-context]
#
# The script will:
#   1. Export kubeconfig from current kubectl configuration
#   2. Create a secret 'cert-sync-kubeconfig' in cert-manager namespace
#   3. The CronJob will mount this secret as /kubeconfig/config

set -euo pipefail

CONTEXT="${1:-rancher-manager}"
SECRET_NAME="cert-sync-kubeconfig"
NAMESPACE="cert-manager"

echo "📋 Creating kubeconfig secret for cert-sync CronJob..."
echo "   Context: ${CONTEXT}"
echo "   Secret: ${SECRET_NAME}"
echo "   Namespace: ${NAMESPACE}"
echo ""

# Check if context exists
if ! kubectl config get-contexts "${CONTEXT}" >/dev/null 2>&1; then
    echo "❌ Error: kubectl context '${CONTEXT}' not found"
    echo "   Available contexts:"
    kubectl config get-contexts -o name
    exit 1
fi

# Export current kubeconfig (with all contexts) to a temporary file
TEMP_KUBECONFIG=$(mktemp)
export KUBECONFIG="${HOME}/.kube/config"
if [[ ! -f "${KUBECONFIG}" ]]; then
    echo "❌ Error: kubeconfig file not found at ${KUBECONFIG}"
    exit 1
fi

cp "${KUBECONFIG}" "${TEMP_KUBECONFIG}"

echo "📝 Exporting kubeconfig from current kubectl configuration..."
echo "   Found contexts:"
kubectl config get-contexts -o name

# Create or update the secret
echo ""
echo "🔐 Creating secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."

kubectl --context="${CONTEXT}" create secret generic "${SECRET_NAME}" \
    --from-file=config="${TEMP_KUBECONFIG}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | \
kubectl --context="${CONTEXT}" apply -f -

# Add labels to the secret
kubectl --context="${CONTEXT}" label secret "${SECRET_NAME}" \
    --namespace="${NAMESPACE}" \
    app=cert-manager \
    managed-by=gitops \
    purpose=cert-sync \
    --overwrite

# Cleanup
rm -f "${TEMP_KUBECONFIG}"

echo ""
echo "✅ Secret '${SECRET_NAME}' created/updated successfully!"
echo ""
echo "ℹ️  Note: The secret contains kubeconfig with contexts for all clusters."
echo "   Ensure the kubeconfig has valid credentials for:"
echo "   - rancher-manager (read secrets)"
echo "   - nprd-apps (write secrets)"
echo "   - poc-apps (write secrets)"
echo "   - prd-apps (write secrets)"
echo ""
echo "   The CronJob will automatically sync certificates daily at 2 AM UTC."
