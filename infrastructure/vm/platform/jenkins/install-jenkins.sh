#!/bin/bash
set -e

# =============================================================================
# Jenkins Installation Script
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)/services"

echo ">>> [1/5] Creating Jenkins namespace and RBAC..."
kubectl apply -f "${SCRIPT_DIR}/00-namespace.yaml"

echo ">>> [2/5] Creating ride-hailing namespace (target for deployments)..."
if [ -f "${SERVICES_DIR}/namespace.yaml" ]; then
    kubectl apply -f "${SERVICES_DIR}/namespace.yaml"
else
    # Fallback: create namespace directly if file not found
    kubectl create namespace ride-hailing --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace ride-hailing istio-injection=enabled --overwrite
fi

echo ">>> [3/5] Setting up RBAC and storage..."
kubectl apply -f "${SCRIPT_DIR}/01-rbac.yaml"
kubectl apply -f "${SCRIPT_DIR}/02-storage.yaml"

echo ">>> [4/5] Deploying Jenkins..."
kubectl apply -f "${SCRIPT_DIR}/03-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/04-service.yaml"

echo ">>> [5/5] Waiting for Jenkins to be ready (this may take 2-3 minutes)..."
kubectl -n jenkins rollout status deployment/jenkins --timeout=300s

# Get initial admin password
echo ""
echo "=============================================="
echo "  Jenkins Installation Complete!"
echo "=============================================="
echo ""
echo "Access Jenkins at: http://<NODE_IP>:30808"
echo ""
echo "To get the initial admin password, run:"
echo "  kubectl -n jenkins exec -it $(kubectl -n jenkins get pod -l app=jenkins -o jsonpath='{.items[0].metadata.name}') -- cat /var/jenkins_home/secrets/initialAdminPassword"
echo ""
