#!/bin/bash
set -e

# =============================================================================
# Istio Installation Script (Minimal Profile for Resource-Constrained Clusters)
# =============================================================================

# Save script directory before changing directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISTIO_VERSION="1.27.2"
INSTALL_DIR="/tmp/istio-install"

echo ">>> [1/8] Downloading Istio ${ISTIO_VERSION}..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

if [ ! -f "istio-${ISTIO_VERSION}/bin/istioctl" ]; then
    curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
fi

export PATH="${INSTALL_DIR}/istio-${ISTIO_VERSION}/bin:$PATH"

echo ">>> [2/8] Verifying istioctl..."
istioctl version --remote=false

echo ">>> [3/8] Checking Calico CNI compatibility..."
# Check if Calico is using BPF mode with incompatible load balancing
if kubectl get felixconfiguration default &> /dev/null 2>&1; then
    BPF_LB=$(kubectl get felixconfiguration default -o jsonpath='{.spec.bpfConnectTimeLoadBalancing}' 2>/dev/null || echo "")
    if [ "$BPF_LB" = "TCP" ]; then
        echo "Detected incompatible Calico BPF setting, fixing..."
        kubectl patch felixconfiguration default --type=merge -p '{"spec":{"bpfConnectTimeLoadBalancing":"Disabled"}}'
        echo "Restarting Calico pods..."
        kubectl -n calico-system rollout restart daemonset calico-node
        echo "Waiting for Calico to stabilize..."
        sleep 10
        kubectl -n calico-system rollout status daemonset calico-node --timeout=120s
        echo "Calico configuration fixed"
    elif [ -z "$BPF_LB" ] || [ "$BPF_LB" = "Disabled" ]; then
        echo "Calico configuration is compatible"
    fi
else
    echo "No FelixConfiguration found, skipping Calico check"
fi

echo ">>> [4/8] Installing Istio with Minimal Profile..."
# Using minimal profile with reduced resources for 9GB cluster
istioctl install -y -f "${SCRIPT_DIR}/istio-operator.yaml"

echo ">>> [5/8] Waiting for Istio components to be ready..."
kubectl -n istio-system wait --for=condition=available deployment/istiod --timeout=300s
kubectl -n istio-system wait --for=condition=available deployment/istio-ingressgateway --timeout=300s

echo ">>> [6/8] Verifying installation..."
kubectl get pods -n istio-system
echo ""
echo "Checking Istio version..."
istioctl version

echo ">>> [7/8] Deploying Istio Gateway for ride-hailing services..."
kubectl apply -f "${SCRIPT_DIR}/gateway.yaml"

echo ">>> [8/8] Applying service namespace..."
kubectl apply -f "${SCRIPT_DIR}/service-namespace.yaml"

echo ""
echo "=============================================="
echo "  Istio Installation Complete!"
echo "=============================================="
echo ""
echo "Ingress Gateway NodePorts:"
echo "  - HTTP:  30080"
echo "  - HTTPS: 30443"
echo ""
echo "Gateway Configuration:"
kubectl -n ride-hailing get gateway
echo ""
echo "To enable sidecar injection for a namespace:"
echo "  kubectl label namespace <your-namespace> istio-injection=enabled"
echo ""
