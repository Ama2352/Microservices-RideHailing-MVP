#!/bin/bash
# =============================================================================
# Install Prometheus Monitoring Stack
# Deploys Prometheus server for metrics collection and monitoring
# =============================================================================
set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NAMESPACE="monitoring"
COMPONENT="Prometheus"
MANIFEST_DIR="$(dirname "$0")"

# -----------------------------------------------------------------------------
# Color output
# -----------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------
log_info "Starting ${COMPONENT} installation..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl first."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

# -----------------------------------------------------------------------------
# Deploy Prometheus
# -----------------------------------------------------------------------------
log_info "Creating namespace: ${NAMESPACE}"
kubectl apply -f "${MANIFEST_DIR}/00-namespace.yaml"

log_info "Configuring RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)"
kubectl apply -f "${MANIFEST_DIR}/01-rbac.yaml"

log_info "Creating Prometheus configuration"
kubectl apply -f "${MANIFEST_DIR}/02-config.yaml"

log_info "Setting up persistent storage"
kubectl apply -f "${MANIFEST_DIR}/03-storage.yaml"

log_info "Deploying Prometheus server"
kubectl apply -f "${MANIFEST_DIR}/04-deployment.yaml"

log_info "Creating Prometheus service"
kubectl apply -f "${MANIFEST_DIR}/05-service.yaml"

log_info "Deploying Node Exporter (host metrics collector)"
kubectl apply -f "${MANIFEST_DIR}/06-node-exporter.yaml"

# -----------------------------------------------------------------------------
# Wait for deployment
# -----------------------------------------------------------------------------
log_info "Waiting for Prometheus to be ready..."
kubectl -n ${NAMESPACE} rollout status deployment/prometheus --timeout=180s

log_info "Waiting for Node Exporter DaemonSet..."
sleep 5
EXPECTED_NODES=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl -n ${NAMESPACE} get daemonset node-exporter -o jsonpath='{.status.numberReady}')
log_info "Node Exporter: ${READY_NODES}/${EXPECTED_NODES} pods ready"

# -----------------------------------------------------------------------------
# Verify installation
# -----------------------------------------------------------------------------
log_info "Verifying installation..."
echo ""
echo "=== Pod Status ==="
kubectl -n ${NAMESPACE} get pods -l app=prometheus

echo ""
echo "=== Service ==="
kubectl -n ${NAMESPACE} get svc prometheus

echo ""
echo "=== PVC Status ==="
kubectl -n ${NAMESPACE} get pvc prometheus-pvc

echo ""
echo "=== Node Exporter Status ==="
kubectl -n ${NAMESPACE} get daemonset node-exporter
kubectl -n ${NAMESPACE} get pods -l app=node-exporter -o wide

# -----------------------------------------------------------------------------
# Access information
# -----------------------------------------------------------------------------
NODE_PORT=$(kubectl -n ${NAMESPACE} get svc prometheus -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
log_info "${COMPONENT} installation completed successfully!"
echo ""
echo "Access Prometheus UI:"
echo "  URL: http://${NODE_IP}:${NODE_PORT}"
echo "  Internal: http://prometheus.${NAMESPACE}.svc.cluster.local:9090"
echo ""
echo "With your Vagrant setup:"
echo "  Master:   http://192.168.242.10:${NODE_PORT}"
echo "  Worker-1: http://192.168.242.11:${NODE_PORT}"
echo "  Worker-2: http://192.168.242.12:${NODE_PORT}"
echo ""
log_warn "Data retention: 6 hours (configured for resource-constrained setup)"
