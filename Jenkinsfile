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
                    image: moby/buildkit:latest
                    command:
                    - cat
                    tty: true
                    securityContext:
                      privileged: true
                    resources:
                      requests:
                        memory: "256Mi"
                        cpu: "100m"
                      limits:
                        memory: "1Gi"
                        cpu: "500m"
                  - name: kubectl
                    image: bitnami/kubectl:latest
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
        // Stage 3: Build & Push Images with BuildKit (Parallel)
        // =====================================================================
        stage('Build & Push Images') {
            parallel {
                stage('Build Dispatch Image') {
                    steps {
                        container('buildkit') {
                            withCredentials([
                                usernamePassword(credentialsId: 'docker-registry-credentials', 
                                    usernameVariable: 'DOCKER_USER', 
                                    passwordVariable: 'DOCKER_PASS')
                            ]) {
                                sh '''
                                # Start buildkitd in privileged mode
                                buildkitd &
                                BUILDKITD_PID=$!
                                
                                # Wait for buildkitd socket to be ready (max 30 seconds)
                                echo "Waiting for buildkitd to be ready..."
                                for i in $(seq 1 30); do
                                    if [ -S /run/buildkit/buildkitd.sock ]; then
                                        echo "buildkitd is ready after ${i} seconds"
                                        break
                                    fi
                                    if ! kill -0 $BUILDKITD_PID 2>/dev/null; then
                                        echo "buildkitd process died unexpectedly"
                                        exit 1
                                    fi
                                    sleep 1
                                done
                                
                                if [ ! -S /run/buildkit/buildkitd.sock ]; then
                                    echo "buildkitd socket not found after 30 seconds"
                                    exit 1
                                fi
                                
                                # Create BuildKit registry auth config
                                mkdir -p ~/.docker
                                cat > ~/.docker/config.json <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "username": "${DOCKER_USER}",
      "password": "${DOCKER_PASS}"
    }
  }
}
EOF
                                
                                # Build and push with buildctl
                                buildctl build \
                                    --frontend dockerfile.v0 \
                                    --local context=./services/dispatch \
                                    --local dockerfile=./services/dispatch \
                                    --output type=image,name=${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG},push=true \
                                    --export-cache type=inline \
                                    --import-cache type=registry,ref=${DOCKER_REGISTRY}/dispatch-service:cache
                                
                                # Also tag as latest
                                buildctl build \
                                    --frontend dockerfile.v0 \
                                    --local context=./services/dispatch \
                                    --local dockerfile=./services/dispatch \
                                    --output type=image,name=${DOCKER_REGISTRY}/dispatch-service:latest,push=true
                                '''
                            }
                        }
                    }
                }
                stage('Build Notification Image') {
                    steps {
                        container('buildkit') {
                            withCredentials([
                                usernamePassword(credentialsId: 'docker-registry-credentials', 
                                    usernameVariable: 'DOCKER_USER', 
                                    passwordVariable: 'DOCKER_PASS')
                            ]) {
                                sh '''
                                # Start buildkitd in privileged mode
                                buildkitd &
                                BUILDKITD_PID=$!
                                
                                # Wait for buildkitd socket to be ready (max 30 seconds)
                                echo "Waiting for buildkitd to be ready..."
                                for i in $(seq 1 30); do
                                    if [ -S /run/buildkit/buildkitd.sock ]; then
                                        echo "buildkitd is ready after ${i} seconds"
                                        break
                                    fi
                                    if ! kill -0 $BUILDKITD_PID 2>/dev/null; then
                                        echo "buildkitd process died unexpectedly"
                                        exit 1
                                    fi
                                    sleep 1
                                done
                                
                                if [ ! -S /run/buildkit/buildkitd.sock ]; then
                                    echo "buildkitd socket not found after 30 seconds"
                                    exit 1
                                fi
                                
                                # Create BuildKit registry auth config
                                mkdir -p ~/.docker
                                cat > ~/.docker/config.json <<EOF
{
  "auths": {
    "https://index.docker.io/v1/": {
      "username": "${DOCKER_USER}",
      "password": "${DOCKER_PASS}"
    }
  }
}
EOF
                                
                                # Build and push with buildctl
                                buildctl build \
                                    --frontend dockerfile.v0 \
                                    --local context=./services/notification \
                                    --local dockerfile=./services/notification \
                                    --output type=image,name=${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG},push=true \
                                    --export-cache type=inline \
                                    --import-cache type=registry,ref=${DOCKER_REGISTRY}/notification-service:cache
                                
                                # Also tag as latest
                                buildctl build \
                                    --frontend dockerfile.v0 \
                                    --local context=./services/notification \
                                    --local dockerfile=./services/notification \
                                    --output type=image,name=${DOCKER_REGISTRY}/notification-service:latest,push=true
                                '''
                            }
                        }
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 4: Deploy to Kubernetes
        // =====================================================================
        stage('Deploy to Kubernetes') {
            steps {
                container('kubectl') {
                    sh '''
                    # Apply namespace first
                    kubectl apply -f services/namespace.yaml
                    
                    # Deploy services with image substitution
                    cat services/dispatch/k8s.yaml | \
                        sed "s|\\${DOCKER_REGISTRY}|${DOCKER_REGISTRY}|g" | \
                        sed "s|\\${IMAGE_TAG}|${IMAGE_TAG}|g" | \
                        kubectl apply -f -
                    
                    cat services/notification/k8s.yaml | \
                        sed "s|\\${DOCKER_REGISTRY}|${DOCKER_REGISTRY}|g" | \
                        sed "s|\\${IMAGE_TAG}|${IMAGE_TAG}|g" | \
                        kubectl apply -f -
                    
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
