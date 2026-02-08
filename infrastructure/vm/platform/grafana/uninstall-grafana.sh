#!/bin/bash
# =============================================================================
# Uninstall Grafana
# Removes Grafana deployment and configuration
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

# -----------------------------------------------------------------------------
# Confirm deletion
# -----------------------------------------------------------------------------
log_warn "This will remove ${COMPONENT}."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Uninstallation cancelled."
    exit 0
fi

# -----------------------------------------------------------------------------
# Remove Grafana
# -----------------------------------------------------------------------------
log_info "Removing ${COMPONENT}..."

log_info "Deleting service..."
kubectl delete -f "${MANIFEST_DIR}/03-service.yaml" --ignore-not-found=true

log_info "Deleting deployment..."
kubectl delete -f "${MANIFEST_DIR}/02-deployment.yaml" --ignore-not-found=true

log_info "Deleting persistent storage..."
kubectl delete -f "${MANIFEST_DIR}/01-storage.yaml" --ignore-not-found=true
kubectl delete pv grafana-pv --ignore-not-found=true

log_info "Deleting datasource configuration..."
kubectl delete -f "${MANIFEST_DIR}/00-datasource.yaml" --ignore-not-found=true

# -----------------------------------------------------------------------------
# Verify removal
# -----------------------------------------------------------------------------
log_info "Verifying removal..."
sleep 3

REMAINING_PODS=$(kubectl -n ${NAMESPACE} get pods -l app=grafana --no-headers 2>/dev/null | wc -l)

if [ "$REMAINING_PODS" -eq 0 ]; then
    echo ""
    log_info "${COMPONENT} uninstalled successfully!"
    echo ""
    log_warn "Persistent data remains at: /data/grafana on k8s-worker-2"
    log_warn "To fully clean up: ssh k8s-worker-2 'sudo rm -rf /data/grafana'"
else
    log_warn "Some pods still terminating. Check: kubectl -n ${NAMESPACE} get pods -l app=grafana"
fi

echo ""
log_info "Note: Prometheus and node-exporter remain active in the monitoring namespace."
