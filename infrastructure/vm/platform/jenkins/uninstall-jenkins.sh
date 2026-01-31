#!/bin/bash
set -e

# =============================================================================
# Jenkins Uninstallation Script
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> Removing Jenkins resources..."

kubectl delete -f "${SCRIPT_DIR}/04-service.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/03-deployment.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/02-storage.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/01-rbac.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/00-namespace.yaml" --ignore-not-found=true

# Clean up PV (needs to be deleted after PVC)
kubectl delete pv jenkins-pv --ignore-not-found=true

echo ">>> Jenkins uninstalled successfully."
echo ""
echo "NOTE: Data in /data/jenkins on the node is preserved."
echo "      Delete manually if you want to remove all data."
