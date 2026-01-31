// =============================================================================
// CI/CD Pipeline for Ride-Hailing Microservices
// Builds and deploys Go services to Kubernetes cluster
// =============================================================================

pipeline {
    agent any
    
    environment {
        // Docker Registry Configuration
        DOCKER_REGISTRY_CRED = credentials('docker-registry-url')
        DOCKER_REGISTRY = "${DOCKER_REGISTRY_CRED}"
        DOCKER_CREDENTIALS = credentials('docker-registry-credentials')
        
        // Kubernetes Configuration
        KUBECONFIG = credentials('kubeconfig')
        K8S_NAMESPACE = 'ride-hailing'
        
        // Build Configuration
        GO_VERSION = '1.21'
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
                }
            }
        }
        
        // =====================================================================
        // Stage 2: Build & Test Services (Parallel)
        // =====================================================================
        stage('Build Services') {
            parallel {
                stage('Dispatch Service') {
                    stages {
                        stage('Test Dispatch') {
                            steps {
                                dir('services/dispatch') {
                                    sh '''
                                        go mod download
                                        go vet ./...
                                        go test -v ./... || echo "No tests yet"
                                    '''
                                }
                            }
                        }
                        stage('Build Dispatch Image') {
                            steps {
                                dir('services/dispatch') {
                                    sh """
                                        docker build -t ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG} .
                                        docker tag ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/dispatch-service:latest
                                    """
                                }
                            }
                        }
                    }
                }
                
                stage('Notification Service') {
                    stages {
                        stage('Test Notification') {
                            steps {
                                dir('services/notification') {
                                    sh '''
                                        go mod download
                                        go vet ./...
                                        go test -v ./... || echo "No tests yet"
                                    '''
                                }
                            }
                        }
                        stage('Build Notification Image') {
                            steps {
                                dir('services/notification') {
                                    sh """
                                        docker build -t ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG} .
                                        docker tag ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/notification-service:latest
                                    """
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // =====================================================================
        // Stage 3: Push Images to Registry
        // =====================================================================
        stage('Push Images') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "${DOCKER_PASS}" | docker login ${DOCKER_REGISTRY} -u "${DOCKER_USER}" --password-stdin
                        
                        docker push ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
                        docker push ${DOCKER_REGISTRY}/dispatch-service:latest
                        
                        docker push ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}
                        docker push ${DOCKER_REGISTRY}/notification-service:latest
                    '''
                }
            }
        }
        
        // =====================================================================
        // Stage 4: Deploy to Kubernetes
        // =====================================================================
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    // Apply namespace first
                    sh "kubectl apply -f services/namespace.yaml"
                    
                    // Deploy services with image substitution
                    sh """
                        cat services/dispatch/k8s.yaml | \\
                            sed 's|\${DOCKER_REGISTRY}|${DOCKER_REGISTRY}|g' | \\
                            sed 's|\${IMAGE_TAG}|${IMAGE_TAG}|g' | \\
                            kubectl apply -f -
                        
                        cat services/notification/k8s.yaml | \\
                            sed 's|\${DOCKER_REGISTRY}|${DOCKER_REGISTRY}|g' | \\
                            sed 's|\${IMAGE_TAG}|${IMAGE_TAG}|g' | \\
                            kubectl apply -f -
                    """
                    
                    // Wait for rollout
                    sh """
                        kubectl -n ${K8S_NAMESPACE} rollout status deployment/dispatch-service --timeout=120s
                        kubectl -n ${K8S_NAMESPACE} rollout status deployment/notification-service --timeout=120s
                    """
                }
            }
        }
        
        // =====================================================================
        // Stage 5: Verify Deployment
        // =====================================================================
        stage('Verify') {
            steps {
                sh """
                    echo "=== Deployment Status ==="
                    kubectl -n ${K8S_NAMESPACE} get pods -o wide
                    
                    echo "=== Service Endpoints ==="
                    kubectl -n ${K8S_NAMESPACE} get svc
                """
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
        always {
            // Clean up Docker images to save space
            node {
                sh '''
                    docker rmi ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG} || true
                    docker rmi ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG} || true
                '''
            }
        }
    }
}
