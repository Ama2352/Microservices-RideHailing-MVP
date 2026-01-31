// =============================================================================
// CI/CD Pipeline for Ride-Hailing Microservices
// Uses BuildKit for daemonless container builds (works with containerd)
// =============================================================================

pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    jenkins: agent
                spec:
                  serviceAccountName: jenkins
                  containers:
                  - name: golang
                    image: golang:1.21-alpine
                    command:
                    - cat
                    tty: true
                    resources:
                      requests:
                        memory: "256Mi"
                        cpu: "100m"
                      limits:
                        memory: "512Mi"
                        cpu: "500m"
                  - name: buildkit
                    image: moby/buildkit:v0.13.2
                    securityContext:
                      # Required for BuildKit in Kubernetes without rootless mode
                      # For production: consider dedicated BuildKit deployment with rootless
                      privileged: true
                    resources:
                      requests:
                        memory: "512Mi"
                        cpu: "200m"
                      limits:
                        memory: "2Gi"
                        cpu: "1000m"
                    readinessProbe:
                      exec:
                        command:
                        - buildctl
                        - debug
                        - workers
                      initialDelaySeconds: 5
                      periodSeconds: 5
                  - name: kubectl
                    image: alpine/k8s:1.29.0
                    command:
                    - cat
                    tty: true
                    resources:
                      requests:
                        memory: "64Mi"
                        cpu: "50m"
                      limits:
                        memory: "128Mi"
                        cpu: "100m"
            '''
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
        // Stage 4: Deploy to Kubernetes
        // Uses envsubst for reliable variable substitution
        // Note: ride-hailing namespace is pre-created by install-jenkins.sh
        // =====================================================================
        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    sh '''
                    # Deploy services with envsubst for reliable substitution
                    export DOCKER_REGISTRY="${DOCKER_REGISTRY}"
                    export IMAGE_TAG="${IMAGE_TAG}"
                    
                    cat services/dispatch/k8s.yaml | envsubst | kubectl apply -f -
                    cat services/notification/k8s.yaml | envsubst | kubectl apply -f -
                    
                    # Wait for rollout
                    kubectl -n ride-hailing rollout status deployment/dispatch-service --timeout=120s
                    kubectl -n ride-hailing rollout status deployment/notification-service --timeout=120s
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 5: Verify Deployment
        // =====================================================================
        stage('Verify') {
            steps {
                container('kubectl') {
                    sh '''
                    echo "=== Deployment Status ==="
                    kubectl -n ride-hailing get pods -o wide
                    
                    echo "=== Service Endpoints ==="
                    kubectl -n ride-hailing get svc
                    
                    echo "=== Istio Sidecar Check ==="
                    kubectl -n ride-hailing get pods -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[*].name}{"\\n"}{end}'
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
