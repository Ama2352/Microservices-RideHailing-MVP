#!/bin/bash
set -e

# =============================================================================
# Istio Installation Script (Minimal Profile for Resource-Constrained Clusters)
# =============================================================================

# Save script directory before changing directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISTIO_VERSION="1.27.2"
INSTALL_DIR="/tmp/istio-install"

echo ">>> [1/5] Downloading Istio ${ISTIO_VERSION}..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

if [ ! -f "istio-${ISTIO_VERSION}/bin/istioctl" ]; then
    curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
fi

export PATH="${INSTALL_DIR}/istio-${ISTIO_VERSION}/bin:$PATH"

echo ">>> [2/5] Verifying istioctl..."
istioctl version --remote=false

echo ">>> [3/5] Checking Calico CNI compatibility..."
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

echo ">>> [4/5] Installing Istio with Minimal Profile..."
# Using minimal profile with reduced resources for 9GB cluster
istioctl install -y -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: istio-minimal
spec:
  profile: minimal
  
  # Mesh configuration
  meshConfig:
    accessLogFile: /dev/stdout
    defaultConfig:
      proxyMetadata:
        ISTIO_META_DNS_CAPTURE: "true"
  
  components:
    # Control Plane (istiod) - Reduced resources
    pilot:
      enabled: true
      k8s:
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        replicaCount: 1
        
    # Ingress Gateway - Essential for external traffic
    ingressGateways:
      - name: istio-ingressgateway
        enabled: true
        k8s:
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          replicaCount: 1
          service:
            type: NodePort
            ports:
              - name: http2
                port: 80
                targetPort: 8080
                nodePort: 30080
              - name: https
                port: 443
                targetPort: 8443
                nodePort: 30443
    
    # Disable Egress Gateway (not needed for MVP)
    egressGateways:
      - name: istio-egressgateway
        enabled: false
  
  # Global settings
  values:
    global:
      proxy:
        resources:
          requests:
            cpu: 10m
            memory: 40Mi
          limits:
            cpu: 100m
            memory: 128Mi
    
    # Disable autoscaling to use fixed replica count
    gateways:
      istio-ingressgateway:
        autoscaleEnabled: false
EOF

echo ">>> [5/5] Waiting for Istio components to be ready..."
kubectl -n istio-system wait --for=condition=available deployment/istiod --timeout=300s
kubectl -n istio-system wait --for=condition=available deployment/istio-ingressgateway --timeout=300s

echo ">>> [6/5] Verifying installation..."
kubectl get pods -n istio-system
echo ""
echo "Checking Istio version..."
istioctl version

echo ">>> [7/7] Deploying Istio Gateway for ride-hailing services..."
kubectl apply -f "${SCRIPT_DIR}/gateway.yaml"

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
