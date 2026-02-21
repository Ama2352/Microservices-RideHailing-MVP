#!/bin/bash
set -e

# =============================================================================
# Jenkins VM Setup
# Installs Docker and runs Jenkins controller as a container.
# Data volume: /data/jenkins (persisted on this VM)
# UI port:     8080
# JNLP port:   50000  (agent callback from K8s cluster)
# =============================================================================

JENKINS_IMAGE="jenkins/jenkins:lts-jdk17"
JENKINS_HOME="/data/jenkins"
JENKINS_CONTAINER="jenkins"
JENKINS_URL="http://192.168.242.13:8080"

# JVM heap tuned for 2 GB VM (OS + Docker ~300 MB, leaves ~1.7 GB for JVM)
JAVA_OPTS="-Xms256m -Xmx768m -Djava.awt.headless=true"

# -----------------------------------------------------------------------------
# 1. Install Docker
# -----------------------------------------------------------------------------
echo ">>> [1/4] Installing Docker..."
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io

systemctl enable docker
systemctl start docker

# Add vagrant user to docker group
echo ">>> Adding vagrant user to docker group..."
usermod -aG docker vagrant

# -----------------------------------------------------------------------------
# 2. Prepare Jenkins data directory
# -----------------------------------------------------------------------------
echo ">>> [2/4] Preparing Jenkins data directory at ${JENKINS_HOME}..."
mkdir -p "${JENKINS_HOME}"
chown -R 1000:1000 "${JENKINS_HOME}"

# -----------------------------------------------------------------------------
# 3. Pull Jenkins image
# -----------------------------------------------------------------------------
echo ">>> [3/4] Pulling ${JENKINS_IMAGE}..."
docker pull "${JENKINS_IMAGE}"

# -----------------------------------------------------------------------------
# 4. Run Jenkins controller
# -----------------------------------------------------------------------------
echo ">>> [4/4] Starting Jenkins container..."

# Stop and remove any existing container before (re)provisioning
docker rm -f "${JENKINS_CONTAINER}" 2>/dev/null || true

docker run -d \
  --name "${JENKINS_CONTAINER}" \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 50000:50000 \
  -v "${JENKINS_HOME}:/var/jenkins_home" \
  -e "JAVA_OPTS=${JAVA_OPTS}" \
  -e "JENKINS_OPTS=--httpPort=8080" \
  "${JENKINS_IMAGE}"

echo ""
echo "=============================================="
echo "  Jenkins controller started"
echo "=============================================="
echo ""
echo "  UI:         ${JENKINS_URL}"
echo "  JNLP port:  50000  (agent callback from K8s)"
echo "  Data:       ${JENKINS_HOME}"
echo ""
echo "  Initial admin password (after ~90s startup):"
echo "    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo ""
echo "  Kubernetes plugin config:"
echo "    Jenkins URL:    ${JENKINS_URL}"
echo "    Jenkins Tunnel: 192.168.242.13:50000"
echo "    K8s API:        https://192.168.242.10:6443"
echo "=============================================="
