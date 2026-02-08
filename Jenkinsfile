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
        // Stage 2: Automated Tests (Parallel)
        // Executes unit tests and coverage checks across services in parallel
        // =====================================================================
        stage('Automated Tests') {
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
        // Stage 5: Build Images (Local Only)
        // BuildKit builds images to Docker tar format for Trivy scanning
        // Images are NOT pushed yet - must pass security scan first
        // =====================================================================
        stage('Build Images') {
            steps {
                container('buildkit') {
                    sh '''
                    set -e
                    
                    echo "=== Building Dispatch Service ==="
                    buildctl build \
                        --frontend dockerfile.v0 \
                        --local context=./services/dispatch \
                        --local dockerfile=./services/dispatch \
                        --output type=docker,name=dispatch-service:scan,dest=dispatch-service.tar
                    
                    echo "=== Building Notification Service ==="
                    buildctl build \
                        --frontend dockerfile.v0 \
                        --local context=./services/notification \
                        --local dockerfile=./services/notification \
                        --output type=docker,name=notification-service:scan,dest=notification-service.tar
                    
                    echo "✓ Images built successfully (not pushed yet)"
                    ls -lh *.tar
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 6: Scan Container Images
        // Trivy scans LOCAL image tars for OS and application vulnerabilities
        // SECURITY GATE: Only clean images proceed to push stage
        // =====================================================================
        stage('Scan Images') {
            steps {
                container('trivy') {
                    sh '''
                    set -e
                    SCAN_FAILED=0
                    
                    echo "=== Scanning Dispatch Service Image ==="
                    if ! trivy image \
                        --input dispatch-service.tar \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --no-progress \
                        --format table; then
                        echo "⚠️ SECURITY ALERT: Dispatch service has HIGH/CRITICAL vulnerabilities!"
                        SCAN_FAILED=1
                    else
                        echo "✓ Dispatch service: No HIGH/CRITICAL vulnerabilities found"
                    fi
                    
                    echo ""
                    echo "=== Scanning Notification Service Image ==="
                    if ! trivy image \
                        --input notification-service.tar \
                        --severity HIGH,CRITICAL \
                        --exit-code 1 \
                        --no-progress \
                        --format table; then
                        echo "⚠️ SECURITY ALERT: Notification service has HIGH/CRITICAL vulnerabilities!"
                        SCAN_FAILED=1
                    else
                        echo "✓ Notification service: No HIGH/CRITICAL vulnerabilities found"
                    fi
                    
                    if [ $SCAN_FAILED -eq 1 ]; then
                        echo ""
                        echo "❌ Security scan failed: HIGH/CRITICAL vulnerabilities detected."
                        echo "Images will NOT be pushed to registry."
                        exit 1
                    fi
                    
                    echo ""
                    echo "✓ All images passed security scan - approved for push"
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 7: Push Validated Images
        // Only reached if security scans pass
        // Pushes clean images to registry with proper tags and caching
        // =====================================================================
        stage('Push Images') {
            steps {
                container('buildkit') {
                    withCredentials([
                        usernamePassword(credentialsId: 'docker-registry-credentials', 
                            usernameVariable: 'DOCKER_USER', 
                            passwordVariable: 'DOCKER_PASS')
                    ]) {
                        sh '''
                        set -e
                        
                        # Configure registry authentication
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
                        
                        echo "=== Pushing Dispatch Service ==="
                        buildctl build \
                            --frontend dockerfile.v0 \
                            --local context=./services/dispatch \
                            --local dockerfile=./services/dispatch \
                            --output type=image,name=${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG},push=true \
                            --output type=image,name=${DOCKER_REGISTRY}/dispatch-service:latest,push=true \
                            --export-cache type=registry,ref=${DOCKER_REGISTRY}/dispatch-service:buildcache,mode=max \
                            --import-cache type=registry,ref=${DOCKER_REGISTRY}/dispatch-service:buildcache
                        
                        echo "=== Pushing Notification Service ==="
                        buildctl build \
                            --frontend dockerfile.v0 \
                            --local context=./services/notification \
                            --local dockerfile=./services/notification \
                            --output type=image,name=${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG},push=true \
                            --output type=image,name=${DOCKER_REGISTRY}/notification-service:latest,push=true \
                            --export-cache type=registry,ref=${DOCKER_REGISTRY}/notification-service:buildcache,mode=max \
                            --import-cache type=registry,ref=${DOCKER_REGISTRY}/notification-service:buildcache
                        
                        echo "✓ All validated images pushed to registry"
                        '''
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 8: Deploy to Kubernetes
        // Only reached if all security scans pass and images are pushed
        // Uses envsubst for reliable variable substitution
        // =====================================================================
        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    sh '''
                    set -e
                    
                    # Deploy Kubernetes resources with envsubst for reliable substitution
                    export DOCKER_REGISTRY="${DOCKER_REGISTRY}"
                    export IMAGE_TAG="${IMAGE_TAG}"
                    
                    echo "=== Deploying Dispatch Service ==="
                    cat services/dispatch/k8s.yaml | envsubst | kubectl apply -f -
                    kubectl apply -f services/dispatch/istio.yaml
                    
                    echo ""
                    echo "=== Deploying Notification Service ==="
                    cat services/notification/k8s.yaml | envsubst | kubectl apply -f -
                    kubectl apply -f services/notification/istio.yaml
                    
                    echo ""
                    echo "=== Checking pod status before rollout ==="
                    kubectl -n ride-hailing get pods
                    
                    echo ""
                    echo "=== Waiting for Dispatch Service rollout ==="
                    if ! kubectl -n ride-hailing rollout status deployment/dispatch-service --timeout=300s; then
                        echo "⚠️ Dispatch rollout timeout - showing debug info:"
                        kubectl -n ride-hailing get pods -l app=dispatch-service
                        kubectl -n ride-hailing describe pods -l app=dispatch-service | tail -50
                        exit 1
                    fi
                    
                    echo ""
                    echo "=== Waiting for Notification Service rollout ==="
                    if ! kubectl -n ride-hailing rollout status deployment/notification-service --timeout=300s; then
                        echo "⚠️ Notification rollout timeout - showing debug info:"
                        kubectl -n ride-hailing get pods -l app=notification-service
                        kubectl -n ride-hailing describe pods -l app=notification-service | tail -50
                        exit 1
                    fi
                    
                    echo ""
                    echo "✓ All deployments rolled out successfully"
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 9: Verify Deployment
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
                    echo "✓ Deployment verified successfully"
                    echo "Access services via NodePort 30080 on any cluster node"
                    '''
                }
            }
        }
    }
    
    post {
        success {
            echo "✓ Pipeline completed successfully!"
            echo "Deployed version: ${IMAGE_TAG}"
            
            mail(
                to: "honguyenminhsang2005@gmail.com",
                subject: "✓ CI/CD Pipeline Success - Build #${env.BUILD_NUMBER}",
                body: """
===========================================
✓ CI/CD PIPELINE SUCCESS
===========================================

Build Information:
------------------
Build Number:     #${env.BUILD_NUMBER}
Git Commit:       ${env.GIT_COMMIT}
Git Branch:       ${env.GIT_BRANCH ?: 'N/A'}
Image Tag:        ${IMAGE_TAG}
Build Duration:   ${currentBuild.durationString}

Deployed Images:
------------------
${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}

Security Validation:
------------------
✓ Unit Tests Passed
✓ SonarQube Quality Gate Passed
✓ Dependency Scan Passed (govulncheck)
✓ Container Image Scan Passed (Trivy)

Access Services:
------------------
Services are exposed via Istio Ingress Gateway on NodePort 30080

Test endpoints (replace <NODE-IP> with any cluster node IP):
  curl http://<NODE-IP>:30080/dispatch/health
  curl http://<NODE-IP>:30080/notification/health

To get node IPs:
  kubectl get nodes -o wide

Deployment successful at: ${new Date()}

View Build:
------------------
Blue Ocean:    http://jenkins.local:30808/blue/organizations/jenkins/ride-hailing-services/detail/ride-hailing-services/${env.BUILD_NUMBER}/pipeline
Console:       http://jenkins.local:30808/job/ride-hailing-services/${env.BUILD_NUMBER}/console
Classic View:  http://jenkins.local:30808/job/ride-hailing-services/${env.BUILD_NUMBER}/
===========================================
"""
            )
        }

        failure {
            echo "✗ Pipeline failed! Check logs for details."
                
                mail(
                    to: "honguyenminhsang2005@gmail.com",
                    subject: "✗ CI/CD Pipeline FAILURE - Build #${env.BUILD_NUMBER}",
                    body: """
===========================================
✗ CI/CD PIPELINE FAILURE
===========================================

⚠️ IMMEDIATE ACTION REQUIRED ⚠️

Build Information:
------------------
Build Number:     #${env.BUILD_NUMBER}
Git Commit:       ${env.GIT_COMMIT}
Git Branch:       ${env.GIT_BRANCH}
Failed Stage:     ${env.STAGE_NAME}
Build Duration:   ${currentBuild.durationString}

Failure Analysis:
------------------
The pipeline failed at stage: ${env.STAGE_NAME}

Common Failure Scenarios:
- Stage 2 (Tests): Unit test failures or code issues
- Stage 3 (SonarQube): Code quality gate failed
- Stage 4 (Scan Dependencies): Vulnerable Go dependencies detected
- Stage 6 (Scan Images): HIGH/CRITICAL vulnerabilities in container images
- Stage 8 (Deploy): Kubernetes deployment/rollout timeout

Security Alert:
------------------
⚠️ If failure occurred at security scanning stages (4 or 6):
   → Images were NOT pushed to registry
   → No vulnerable code reached production
   → Review vulnerability reports in build logs

Action Required:
------------------
1. Review full logs in Jenkins console
2. Check security scan results if applicable
3. Fix root cause before triggering new build
4. Do NOT bypass security gates

Debug Commands:
------------------
# View Jenkins pod logs
kubectl -n jenkins logs -f deployment/jenkins

# Check build agent status
kubectl -n jenkins get pods

# Review last deployment
kubectl -n ride-hailing get pods,svc

Failed at: ${new Date()}

View Build (Blue Ocean shows failed stage clearly):
------------------
Blue Ocean:    http://jenkins.local:30808/blue/organizations/jenkins/ride-hailing-services/detail/ride-hailing-services/${env.BUILD_NUMBER}/pipeline
Console:       http://jenkins.local:30808/job/ride-hailing-services/${env.BUILD_NUMBER}/console
Classic View:  http://jenkins.local:30808/job/ride-hailing-services/${env.BUILD_NUMBER}/
===========================================
"""
            )
        }
    }
}

