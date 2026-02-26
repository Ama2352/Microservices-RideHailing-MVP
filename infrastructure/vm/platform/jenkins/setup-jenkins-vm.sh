#!/bin/bash
set -e

[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"

# =============================================================================
# Jenkins VM Setup
# Installs Docker and runs Jenkins controller as a container.
# Data volume: /data/jenkins (persisted on this VM)
# UI port:     8080
#
# DooD (Docker-outside-of-Docker): CI stages run as sibling containers on
# this VM. Two requirements:
#   1. /var/run/docker.sock is mounted so Jenkins can manage siblings.
#   2. JENKINS_HOME path must be identical on the host and inside the
#      Jenkins container (/data/jenkins:/data/jenkins). The Docker daemon
#      runs on the HOST — when Jenkins mounts a workspace into a sibling
#      container, it passes the in-container path. If host and container
#      paths differ, the daemon cannot resolve the directory.
# =============================================================================

JENKINS_IMAGE="jenkins/jenkins:lts-jdk17"
JENKINS_HOME="/data/jenkins"
JENKINS_CONTAINER="jenkins"
JENKINS_URL="http://192.168.242.13:8080"

# JVM heap tuned for 3 GB VM: leaves ~2 GB headroom for Docker agent containers
JAVA_OPTS="-Xms512m -Xmx1024m -Djava.awt.headless=true -Dorg.jenkinsci.plugins.durabletask.BourneShellScript.HEARTBEAT_CHECK_INTERVAL=86400"

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

# Add vagrant user to docker group (idempotent)
if ! id -nG vagrant | grep -qw docker; then
    echo ">>> Adding vagrant user to docker group..."
    usermod -aG docker vagrant
else
    echo ">>> vagrant already in docker group, skipping."
fi

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

DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)

docker run -d \
  --name "${JENKINS_CONTAINER}" \
  --restart unless-stopped \
  --group-add "${DOCKER_GID}" \
  -p 8080:8080 \
  -p 50000:50000 \
  -v "${JENKINS_HOME}:${JENKINS_HOME}" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /usr/bin/docker:/usr/bin/docker:ro \
  -e "JENKINS_HOME=${JENKINS_HOME}" \
  -e "JAVA_OPTS=${JAVA_OPTS}" \
  -e "JENKINS_OPTS=--httpPort=8080" \
  "${JENKINS_IMAGE}"

echo ""
echo "=============================================="
echo "  Jenkins controller started"
echo "=============================================="
echo ""
echo "  UI:    ${JENKINS_URL}"
echo "  Data:  ${JENKINS_HOME}"
echo ""
echo "  Initial admin password (after ~90s startup):"
echo "    docker exec jenkins cat ${JENKINS_HOME}/secrets/initialAdminPassword"
echo ""
echo "  Required plugins: Docker Pipeline, Git, Pipeline"
echo ""
echo "  After Jenkins is up, configure credentials:"
echo "    docker-registry-credentials  (Username/Password)"
echo "    sonarqube-token              (Secret text)"
echo "    k8s-sa-token                 (Secret text — from install-jenkins.sh)"
echo "=============================================="
