#!/bin/bash
set -e

# =============================================================================
# GitHub Webhook Tunnel
# Runs ngrok directly on jenkins-vm (192.168.242.13) to expose Jenkins port
# 8080 to GitHub. Jenkins is external to the K8s cluster, so Istio ingress
# is not involved in webhook delivery.
#
# Run this script ON jenkins-vm, not on k8s-master.
#
# After starting, update the GitHub webhook URL to:
#   https://<ngrok-id>.ngrok-free.dev/github-webhook/
# =============================================================================

JENKINS_PORT=8080

# Install ngrok if not present
if ! command -v ngrok >/dev/null 2>&1; then
  echo ">>> Installing ngrok..."
  curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | sudo tee /etc/apt/sources.list.d/ngrok.list
  sudo apt update -qq && sudo apt install -y -qq ngrok
fi

echo ">>> Starting ngrok tunnel to Jenkins on port ${JENKINS_PORT}..."
echo "    After ngrok starts, update the GitHub webhook URL to:"
echo "    https://<ngrok-id>.ngrok-free.dev/github-webhook/"
echo ""
ngrok http "${JENKINS_PORT}"
