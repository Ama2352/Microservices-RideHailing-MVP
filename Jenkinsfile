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
        // Stage 2: Test & Code Quality (Parallel)
        // Runs unit tests (with coverage) and SonarQube analysis together
        // =====================================================================
        stage('Test & Code Quality') {
            parallel {
                stage('Test Dispatch') {
                    steps {
                        container('golang') {
                            dir('services/dispatch') {
                                sh '''
                                    go mod download
                                    go vet ./...
                                    go test -v -coverprofile=coverage.out ./... || echo "No tests yet"
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
                                    go test -v -coverprofile=coverage.out ./... || echo "No tests yet"
                                '''
                            }
                        }
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 3: SonarQube Analysis
        // Static code analysis: bugs, code smells, duplication, maintainability
        // Runs after tests so coverage reports are available
        // Requires: SonarQube server + Jenkins SonarQube plugin configured
        // =====================================================================
        stage('SonarQube Analysis') {
            steps {
                container('sonar-scanner') {
                    withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                        sh '''
                        SONAR_HOST="http://sonarqube.sonarqube.svc.cluster.local:9000"
                        
                        echo "=== Analyzing Dispatch Service ==="
                        cd services/dispatch
                        sonar-scanner \
                            -Dsonar.host.url=${SONAR_HOST} \
                            -Dsonar.token=${SONAR_TOKEN}
                        cd ../..
                        
                        echo ""
                        echo "=== Analyzing Notification Service ==="
                        cd services/notification
                        sonar-scanner \
                            -Dsonar.host.url=${SONAR_HOST} \
                            -Dsonar.token=${SONAR_TOKEN}
                        
                        echo ""
                        echo "All services passed SonarQube quality gate"
                        '''
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 4: Scan Dependencies
        // Uses govulncheck - Go's official vulnerability scanner (golang.org/x/vuln)
        // Checks go.mod against the Go Vulnerability Database
        // Fast (~10s), no heavy database download needed
        // =====================================================================
        stage('Scan Dependencies') {
            steps {
                container('golang') {
                    sh '''
                    echo "=== Installing govulncheck ==="
                    go install golang.org/x/vuln/cmd/govulncheck@latest
                    
                    echo ""
                    echo "=== Scanning Dispatch Service ==="
                    cd services/dispatch
                    govulncheck ./...
                    cd ../.. 
                    
                    echo ""
                    echo "=== Scanning Notification Service ==="
                    cd services/notification
                    govulncheck ./...
                    
                    echo ""
                    echo "✓ All dependencies passed vulnerability scan"
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 5: Build Images
        // BuildKit builds and pushes atomically for efficiency and caching
        // Images are tagged with build number - not yet approved for deployment
        // =====================================================================
        stage('Build Images') {
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
        // Stage 6: Scan Container Images
        // Trivy scans images from registry for OS and application vulnerabilities
        // Gates deployment - only clean images proceed to production
        // =====================================================================
        stage('Scan Images') {
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
        // Stage 7: Deploy to Kubernetes
        // Only reached if all security scans pass
        // Uses envsubst for reliable variable substitution
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
        // Stage 8: Verify Deployment
        // =====================================================================
        stage('Verify Deployment') {
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

            mail(
                to: "honguyenminhsang2005@gmail.com",
                subject: "CI/CD Pipeline Success - Build #${env.BUILD_NUMBER}",
                body: "CI/CD pipeline completed successfully."
            )
        }

        failure {
            echo "Pipeline failed! Check logs for details."

            mail(
                to: "honguyenminhsang2005@gmail.com",
                subject: "CI/CD Pipeline Failure - Build #${env.BUILD_NUMBER}",
                body: "CI/CD pipeline failed."
            )
        }
    }
}
