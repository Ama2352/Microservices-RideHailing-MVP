#!/bin/bash
set -e

# =============================================================================
# Jenkins K8s Cleanup
# Removes all Jenkins-related K8s resources.
# Run this AFTER data has been migrated to jenkins-vm via migrate-data.sh.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> Removing Jenkins K8s resources..."

# Force-delete any stuck Jenkins pods first. The PVC protection finalizer
# (kubernetes.io/pvc-protection) blocks PVC deletion while any pod — even a
# Terminating one — still references the volume.
kubectl delete pods -n jenkins -l app=jenkins --force --grace-period=0 --ignore-not-found=true

# Strip the pvc-protection finalizer so the delete is not blocked
kubectl patch pvc jenkins-pvc -n jenkins \
  -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

kubectl delete pvc jenkins-pvc -n jenkins --ignore-not-found=true
kubectl delete pv jenkins-pv --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/01-rbac.yaml" --ignore-not-found=true
kubectl delete -f "${SCRIPT_DIR}/00-namespace.yaml" --ignore-not-found=true

echo ""
echo "  Jenkins K8s resources removed."
echo "  /data/jenkins on k8s-worker-2 can now be deleted manually."
