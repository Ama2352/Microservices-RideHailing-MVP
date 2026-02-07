#!/bin/bash
# =============================================================================
# Uninstall SonarQube from Kubernetes
# Removes all resources including persistent data
# =============================================================================
set -e

echo "=== Uninstalling SonarQube ==="
kubectl delete namespace sonarqube --ignore-not-found
kubectl delete pv sonarqube-pv --ignore-not-found=true
echo "SonarQube removed."
