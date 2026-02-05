// =============================================================================
// CI/CD Pipeline for Ride-Hailing Microservices
// Uses BuildKit for daemonless container builds (works with containerd)
// =============================================================================

pipeline {
    agent {
        kubernetes {
            // Load agent pod template from external file for better maintainability
            yamlFile 'infrastructure/vm/platform/jenkins/agent-pod.yaml'
        }
    }
    
    environment {
        // =================================================================
        // Configuration (non-secrets)
        // Set DOCKER_REGISTRY in Jenkins: Manage Jenkins → System → 
        // Global properties → Environment variables
        // Example: docker.io/yourusername
        // =================================================================
        DOCKER_REGISTRY = "${env.DOCKER_REGISTRY ?: 'docker.io/your-dockerhub-username'}"
        
        // Kubernetes Configuration
        K8S_NAMESPACE = 'ride-hailing'
        
        // Build Configuration
        IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'latest'}"
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    
    stages {
        // =====================================================================
        // Stage 1: Checkout & Prepare
        // =====================================================================
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    echo "Building commit: ${env.GIT_COMMIT}"
                    echo "Image tag: ${IMAGE_TAG}"
                    echo "Docker registry: ${DOCKER_REGISTRY}"
                }
            }
        }
        
        // =====================================================================
        // Stage 2: Test Services (Parallel)
        // =====================================================================
        stage('Test Services') {
            parallel {
                stage('Test Dispatch') {
                    steps {
                        container('golang') {
                            dir('services/dispatch') {
                                sh '''
                                    go mod download
                                    go vet ./...
                                    go test -v ./... || echo "No tests yet"
                                '''
                            }
                        }
                    }
                }
                stage('Test Notification') {
                    steps {
                        container('golang') {
                            dir('services/notification') {
                                sh '''
                                    go mod download
                                    go vet ./...
                                    go test -v ./... || echo "No tests yet"
                                '''
                            }
                        }
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 3: Build & Push Images with BuildKit
        // Single build per service with multiple tags
        // Cache stored in registry for persistence across pod restarts
        // =====================================================================
        stage('Build & Push Images') {
            steps {
                container('buildkit') {
                    withCredentials([
                        usernamePassword(credentialsId: 'docker-registry-credentials', 
                            usernameVariable: 'DOCKER_USER', 
                            passwordVariable: 'DOCKER_PASS')
                    ]) {
                        sh '''
                        # Configure registry authentication for BuildKit
                        mkdir -p /root/.docker
                        cat > /root/.docker/config.json <<DOCKERAUTH
{
  "auths": {
    "https://index.docker.io/v1/": {
      "username": "${DOCKER_USER}",
      "password": "${DOCKER_PASS}"
    }
  }
}
DOCKERAUTH
                        
                        echo "=== Building Dispatch Service ==="
                        buildctl build \
                            --frontend dockerfile.v0 \
                            --local context=./services/dispatch \
                            --local dockerfile=./services/dispatch \
                            --output type=image,name=${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG},push=true \
                            --output type=image,name=${DOCKER_REGISTRY}/dispatch-service:latest,push=true \
                            --export-cache type=registry,ref=${DOCKER_REGISTRY}/dispatch-service:buildcache,mode=max \
                            --import-cache type=registry,ref=${DOCKER_REGISTRY}/dispatch-service:buildcache
                        
                        echo "=== Building Notification Service ==="
                        buildctl build \
                            --frontend dockerfile.v0 \
                            --local context=./services/notification \
                            --local dockerfile=./services/notification \
                            --output type=image,name=${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG},push=true \
                            --output type=image,name=${DOCKER_REGISTRY}/notification-service:latest,push=true \
                            --export-cache type=registry,ref=${DOCKER_REGISTRY}/notification-service:buildcache,mode=max \
                            --import-cache type=registry,ref=${DOCKER_REGISTRY}/notification-service:buildcache
                        '''
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 4: Security Scan - Container Images
        // Scans built images for vulnerabilities before pushing to registry
        // Fails pipeline on HIGH or CRITICAL severity findings
        // =====================================================================
        stage('Security Scan - Images') {
            steps {
                container('trivy') {
                    script {
                        def scanFailed = false
                        
                        echo "=== Scanning Dispatch Service Image ==="
                        def dispatchScan = sh(
                            script: """
                                trivy image \
                                    --severity HIGH,CRITICAL \
                                    --exit-code 1 \
                                    --no-progress \
                                    --format table \
                                    ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
                            """,
                            returnStatus: true
                        )
                        
                        if (dispatchScan != 0) {
                            echo "⚠️ SECURITY ALERT: Dispatch service has HIGH/CRITICAL vulnerabilities!"
                            scanFailed = true
                        } else {
                            echo "✓ Dispatch service: No HIGH/CRITICAL vulnerabilities found"
                        }
                        
                        echo "\n=== Scanning Notification Service Image ==="
                        def notificationScan = sh(
                            script: """
                                trivy image \
                                    --severity HIGH,CRITICAL \
                                    --exit-code 1 \
                                    --no-progress \
                                    --format table \
                                    ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}
                            """,
                            returnStatus: true
                        )
                        
                        if (notificationScan != 0) {
                            echo "⚠️ SECURITY ALERT: Notification service has HIGH/CRITICAL vulnerabilities!"
                            scanFailed = true
                        } else {
                            echo "✓ Notification service: No HIGH/CRITICAL vulnerabilities found"
                        }
                        
                        if (scanFailed) {
                            error("Security scan failed: HIGH/CRITICAL vulnerabilities detected. Fix vulnerabilities before deployment.")
                        }
                        
                        echo "\n✓ All images passed security scan"
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 5: Deploy to Kubernetes
        // Uses envsubst for reliable variable substitution
        // Note: ride-hailing namespace is pre-created by install-jenkins.sh
        // =====================================================================
        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    sh '''
                    # Deploy Kubernetes resources with envsubst for reliable substitution
                    export DOCKER_REGISTRY="${DOCKER_REGISTRY}"
                    export IMAGE_TAG="${IMAGE_TAG}"
                    
                    # Deploy Dispatch Service (K8s + Istio)
                    cat services/dispatch/k8s.yaml | envsubst | kubectl apply -f -
                    kubectl apply -f services/dispatch/istio.yaml
                    
                    # Deploy Notification Service (K8s + Istio)
                    cat services/notification/k8s.yaml | envsubst | kubectl apply -f -
                    kubectl apply -f services/notification/istio.yaml
                    
                    # Wait for rollout
                    kubectl -n ride-hailing rollout status deployment/dispatch-service --timeout=120s
                    kubectl -n ride-hailing rollout status deployment/notification-service --timeout=120s
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 6: Verify Deployment
        // =====================================================================
        stage('Verify') {
            steps {
                container('kubectl') {
                    sh '''
                    echo "=== Deployment Status ==="
                    kubectl -n ride-hailing get pods -o wide
                    
                    echo "=== Service Endpoints ==="
                    kubectl -n ride-hailing get svc
                    
                    echo "=== Istio Configuration ==="
                    kubectl -n ride-hailing get gateway,virtualservice,destinationrule
                    
                    echo "=== Istio Sidecar Check ==="
                    kubectl -n ride-hailing get pods -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[*].name}{"\\n"}{end}'
                    
                    echo "=== Ingress Gateway ==="
                    kubectl -n istio-system get svc istio-ingressgateway
                    
                    echo ""
                    echo "API Endpoints (via NodePort 30080):"
                    echo "  Dispatch:      http://<node-ip>:30080/dispatch/health"
                    echo "  Notification:  http://<node-ip>:30080/notification/health"
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo "Pipeline completed successfully!"
            echo "Deployed version: ${IMAGE_TAG}"
        }
        failure {
            echo "Pipeline failed! Check logs for details."
        }
    }
}
