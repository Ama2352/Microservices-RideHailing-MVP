#!/bin/bash
set -e

# =============================================================================
# Jenkins Installation Script
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> [1/4] Creating Jenkins namespace and RBAC..."
kubectl apply -f "${SCRIPT_DIR}/00-namespace.yaml"
kubectl apply -f "${SCRIPT_DIR}/01-rbac.yaml"

echo ">>> [2/4] Setting up storage..."
kubectl apply -f "${SCRIPT_DIR}/02-storage.yaml"

echo ">>> [3/4] Deploying Jenkins..."
kubectl apply -f "${SCRIPT_DIR}/03-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/04-service.yaml"

echo ">>> [4/4] Waiting for Jenkins to be ready (this may take 2-3 minutes)..."
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
