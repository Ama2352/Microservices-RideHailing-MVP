#!/bin/bash
set -e

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
kubectl apply -f "${SCRIPT_DIR}/02-sa-token.yaml"

# Extract SA token for Jenkins CD credential
SA_TOKEN=$(kubectl -n jenkins get secret jenkins-sa-token \
  -o jsonpath='{.data.token}' | base64 --decode)

echo ""
echo "======================================================"
echo "  Jenkins K8s prerequisites ready"
echo "======================================================"
echo ""
echo "  Store the SA token in Jenkins as a Secret text credential:"
echo ""
echo "    Manage Jenkins → Credentials → System → Global credentials"
echo "    → Add Credentials"
echo "      Kind:   Secret text"
echo "      ID:     k8s-sa-token"
echo "      Secret: (paste the token below)"
echo ""
echo "  SA token:"
echo "  ${SA_TOKEN}"
echo ""
echo "  This token is used exclusively by the CD kubectl stage to apply"
echo "  k8s.yaml and istio.yaml manifests to the cluster."
echo "======================================================"

