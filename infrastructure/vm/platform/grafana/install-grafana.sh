#!/bin/bash
# =============================================================================
# Install Grafana
# Deploys Grafana with auto-configured Prometheus datasource
# =============================================================================
set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NAMESPACE="monitoring"
COMPONENT="Grafana"
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

# Check if monitoring namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    log_error "Namespace '${NAMESPACE}' does not exist."
    log_error "Please install Prometheus first (creates monitoring namespace)."
    exit 1
fi

# Check if Prometheus is running
if ! kubectl -n ${NAMESPACE} get svc prometheus &> /dev/null; then
    log_warn "Prometheus service not found. Grafana will not have data source."
    log_warn "Install Prometheus first for full functionality."
fi

# -----------------------------------------------------------------------------
# Deploy Grafana
# -----------------------------------------------------------------------------
log_info "Creating Prometheus datasource configuration"
kubectl apply -f "${MANIFEST_DIR}/00-datasource.yaml"

log_info "Deploying ${COMPONENT}"
kubectl apply -f "${MANIFEST_DIR}/01-deployment.yaml"

log_info "Creating service"
kubectl apply -f "${MANIFEST_DIR}/02-service.yaml"

# -----------------------------------------------------------------------------
# Wait for deployment
# -----------------------------------------------------------------------------
log_info "Waiting for ${COMPONENT} to be ready..."
kubectl -n ${NAMESPACE} rollout status deployment/grafana --timeout=120s

# -----------------------------------------------------------------------------
# Verify installation
# -----------------------------------------------------------------------------
log_info "Verifying installation..."
echo ""
echo "=== Pod Status ==="
kubectl -n ${NAMESPACE} get pods -l app=grafana

echo ""
echo "=== Service ==="
kubectl -n ${NAMESPACE} get svc grafana

# -----------------------------------------------------------------------------
# Test datasource connection
# -----------------------------------------------------------------------------
echo ""
log_info "Testing Prometheus datasource..."
sleep 5

POD_NAME=$(kubectl -n ${NAMESPACE} get pods -l app=grafana -o jsonpath='{.items[0].metadata.name}')
if [ -n "${POD_NAME}" ]; then
    DATASOURCE_TEST=$(kubectl -n ${NAMESPACE} exec ${POD_NAME} -- \
        wget -q -O - http://localhost:3000/api/datasources 2>/dev/null || echo "Failed")
    
    if echo "${DATASOURCE_TEST}" | grep -q "Prometheus"; then
        log_info "✓ Prometheus datasource configured successfully"
    else
        log_warn "Could not verify datasource. Check Grafana UI after login."
    fi
fi

# -----------------------------------------------------------------------------
# Access information
# -----------------------------------------------------------------------------
NODE_PORT=$(kubectl -n ${NAMESPACE} get svc grafana -o jsonpath='{.spec.ports[0].nodePort}')
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
log_info "${COMPONENT} installation completed successfully!"
echo ""
echo "Access Grafana UI:"
echo "  URL: http://${NODE_IP}:${NODE_PORT}"
echo ""
echo "With your Vagrant setup:"
echo "  Master:   http://192.168.242.10:${NODE_PORT}"
echo "  Worker-1: http://192.168.242.11:${NODE_PORT}"
echo "  Worker-2: http://192.168.242.12:${NODE_PORT}"
echo ""
log_info "Authentication: Disabled (anonymous admin access for learning)"
log_warn "Production: Enable authentication and change default credentials!"
echo ""
echo "Next steps:"
echo "  1. Access Grafana UI in your browser"
echo "  2. Verify Prometheus datasource: Configuration → Data Sources"
echo "  3. Import dashboards from Grafana.com or create custom ones"
echo ""
echo "Recommended dashboards:"
echo "  - Node Exporter Full (ID: 1860) - Host metrics"
echo "  - Kubernetes Pod Resources (ID: 6417) - Pod metrics"
echo "  - Go Processes (ID: 6671) - For your Go services"
