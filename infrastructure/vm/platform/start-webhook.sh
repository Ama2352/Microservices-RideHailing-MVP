#!/bin/bash
set -e

# ===== CONFIG =====
NAMESPACE="istio-system"
SERVICE="istio-ingressgateway"
LOCAL_PORT=18080
SERVICE_PORT=80

# ===== CHECK ngrok =====
if ! command -v ngrok >/dev/null 2>&1; then
  echo "❌ ngrok not found. Installing..."
  curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null

  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | sudo tee /etc/apt/sources.list.d/ngrok.list

  sudo apt update && sudo apt install -y ngrok
fi

# ===== START port-forward =====
echo "🚀 Port-forward Istio Ingress..."
kubectl port-forward -n $NAMESPACE svc/$SERVICE \
  $LOCAL_PORT:$SERVICE_PORT >/tmp/port-forward.log 2>&1 &

PF_PID=$!
sleep 3

# ===== START ngrok =====
echo "🌍 Starting ngrok..."
ngrok http $LOCAL_PORT
kill $PF_PID
