#!/bin/bash
set -e

# =============================================================================
# Jenkins K8s Prerequisites
# Sets up everything the K8s cluster needs to support Jenkins agent pods.
# Jenkins controller itself runs on jenkins-vm (192.168.242.13) — not in K8s.
#
# After running this script, configure the Kubernetes cloud in Jenkins UI:
#   Manage Jenkins → Clouds → Kubernetes
#
#   Kubernetes URL:                https://192.168.242.10:6443
#   Kubernetes server cert key:    (paste CA cert — see output below)
#   Credentials:                   Add → Secret text → (paste token — see output below)
#   Jenkins URL:                   http://192.168.242.13:8080
#   Jenkins Tunnel:                192.168.242.13:50000
#   Namespace:                     jenkins
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ride-hailing namespace must exist before RBAC can be applied (jenkins-deployer
# RoleBinding targets that namespace). It is owned by services/namespace.yaml —
# deploy the services layer first if this check fails.
if ! kubectl get namespace ride-hailing &>/dev/null; then
  echo "ERROR: namespace 'ride-hailing' does not exist."
  echo "       Apply services/namespace.yaml before running this script."
  exit 1
fi

echo ">>> [1/3] Creating Jenkins namespace..."
kubectl apply -f "${SCRIPT_DIR}/00-namespace.yaml"

echo ">>> [2/3] Applying RBAC..."
kubectl apply -f "${SCRIPT_DIR}/01-rbac.yaml"

echo ">>> [3/3] Applying ServiceAccount token Secret..."
kubectl apply -f "${SCRIPT_DIR}/05-sa-token.yaml"

# Extract credentials for Jenkins UI configuration
SA_TOKEN=$(kubectl -n jenkins get secret jenkins-sa-token \
  -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl -n jenkins get secret jenkins-sa-token \
  -o jsonpath='{.data.ca\.crt}')

echo ""
echo "======================================================"
echo "  Jenkins K8s prerequisites ready"
echo "======================================================"
echo ""
echo "  Configure Kubernetes cloud in Jenkins UI:"
echo "  Manage Jenkins → Clouds → Kubernetes"
echo ""
echo "  1. Kubernetes URL:"
echo "     https://192.168.242.10:6443"
echo ""
echo "  2. Kubernetes server certificate key (paste this):"
echo "     ${CA_CERT}"
echo ""
echo "  3. Credentials → Add → Secret text (paste this as the secret):"
echo "     ${SA_TOKEN}"
echo ""
echo "  4. Jenkins URL:    http://192.168.242.13:8080"
echo "  5. Jenkins Tunnel: 192.168.242.13:50000"
echo "  6. Namespace:      jenkins"
echo ""
echo "  Click 'Test Connection' — must show 'Connected to Kubernetes'"
echo "======================================================"
