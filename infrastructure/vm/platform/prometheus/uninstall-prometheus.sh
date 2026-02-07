#!/bin/bash
# =============================================================================
# Uninstall Prometheus Monitoring Stack
# Removes Prometheus and cleans up all resources
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

# -----------------------------------------------------------------------------
# Confirm deletion
# -----------------------------------------------------------------------------
log_warn "This will remove ${COMPONENT} and all monitoring data."
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Uninstallation cancelled."
    exit 0
fi

# -----------------------------------------------------------------------------
# Remove Prometheus components
# -----------------------------------------------------------------------------
log_info "Removing ${COMPONENT}..."

log_info "Deleting Node Exporter..."
kubectl delete -f "${MANIFEST_DIR}/06-node-exporter.yaml" --ignore-not-found=true

log_info "Deleting service..."
kubectl delete -f "${MANIFEST_DIR}/05-service.yaml" --ignore-not-found=true

log_info "Deleting deployment..."
kubectl delete -f "${MANIFEST_DIR}/04-deployment.yaml" --ignore-not-found=true

log_info "Deleting storage..."
kubectl delete -f "${MANIFEST_DIR}/03-storage.yaml" --ignore-not-found=true

log_info "Deleting configuration..."
kubectl delete -f "${MANIFEST_DIR}/02-config.yaml" --ignore-not-found=true

log_info "Deleting RBAC..."
kubectl delete -f "${MANIFEST_DIR}/01-rbac.yaml" --ignore-not-found=true

# Optional: keep namespace if other monitoring tools are installed
log_warn "Namespace '${NAMESPACE}' will be preserved (may contain other tools)."
log_info "To remove namespace manually: kubectl delete namespace ${NAMESPACE}"

# -----------------------------------------------------------------------------
# Verify removal
# -----------------------------------------------------------------------------
log_info "Verifying removal..."
REMAINING_PROMETHEUS=$(kubectl -n ${NAMESPACE} get pods -l app=prometheus --no-headers 2>/dev/null | wc -l)
REMAINING_NODE_EXPORTER=$(kubectl -n ${NAMESPACE} get pods -l app=node-exporter --no-headers 2>/dev/null | wc -l)

if [ "$REMAINING_PROMETHEUS" -eq 0 ] && [ "$REMAINING_NODE_EXPORTER" -eq 0 ]; then
    echo ""
    log_info "${COMPONENT} uninstalled successfully!"
else
    log_warn "Some pods still terminating. Check: kubectl -n ${NAMESPACE} get pods"
fi

echo ""
log_warn "Data in /data/prometheus is NOT deleted."
log_info "To remove data: sudo rm -rf /data/prometheus"
