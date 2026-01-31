#!/bin/bash
set -e

# =============================================================================
# Istio Uninstallation Script
# =============================================================================

ISTIO_VERSION="1.20.0"
INSTALL_DIR="/tmp/istio-install"

echo ">>> Uninstalling Istio..."

# Try using istioctl if available
if [ -f "${INSTALL_DIR}/istio-${ISTIO_VERSION}/bin/istioctl" ]; then
    export PATH="${INSTALL_DIR}/istio-${ISTIO_VERSION}/bin:$PATH"
    istioctl uninstall --purge -y
else
    echo "istioctl not found, using kubectl to remove resources..."
    kubectl delete namespace istio-system --ignore-not-found=true
fi

echo ">>> Cleaning up Istio CRDs..."
kubectl get crd | grep 'istio.io' | awk '{print $1}' | xargs -r kubectl delete crd || true

echo ">>> Istio uninstalled successfully."
