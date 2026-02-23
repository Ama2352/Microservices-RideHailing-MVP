#!/bin/bash
# =============================================================================
# Install SonarQube on Kubernetes
# Deploys SonarQube Community Edition with persistent storage
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Installing SonarQube ==="

# Apply manifests in order
kubectl apply -f "${SCRIPT_DIR}/00-namespace.yaml"
kubectl apply -f "${SCRIPT_DIR}/01-storage.yaml"
kubectl apply -f "${SCRIPT_DIR}/02-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/03-service.yaml"

echo "Waiting for SonarQube to be ready (this may take 2-3 minutes)..."
kubectl -n sonarqube rollout status deployment/sonarqube --timeout=180s

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "========================================="
echo "  SonarQube is Ready"
echo "========================================="
echo ""
echo "  URL:         http://${NODE_IP}:30090"
echo "  Credentials: admin / admin"
echo ""
echo "  NEXT STEPS:"
echo "  1. Log in and change the default password"
echo "  2. Go to: Administration → Security → Users → Tokens"
echo "  3. Generate a token (type: Global Analysis Token)"
echo "  4. Add the token to Jenkins:"
echo "     Manage Jenkins → Credentials → Add → Secret text"
echo "     ID: sonarqube-token"
echo "  5. Configure SonarQube server in Jenkins:"
echo "     Manage Jenkins → System → SonarQube servers"
echo "     Name: sonarqube"
  echo "     URL:  http://${NODE_IP}:30090"
  echo "     NOTE: Jenkins runs outside the cluster — use NodePort, NOT cluster-internal DNS"
echo "     Token: select 'sonarqube-token'"
echo "========================================="
