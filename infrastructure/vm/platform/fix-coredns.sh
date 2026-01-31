#!/bin/bash
set -e

# =============================================================================
# Fix CoreDNS to use public DNS servers instead of systemd-resolved
# =============================================================================

echo ">>> Patching CoreDNS ConfigMap to use Google DNS..."

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 8.8.4.4 {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
EOF

echo ">>> Restarting CoreDNS pods..."
kubectl -n kube-system rollout restart deployment coredns

echo ">>> Waiting for CoreDNS to be ready..."
kubectl -n kube-system rollout status deployment coredns --timeout=60s

echo ">>> Testing DNS resolution..."
sleep 5
kubectl run dns-test --image=busybox:1.28 --restart=Never --rm -it -- nslookup google.com

echo ">>> CoreDNS fix complete!"
