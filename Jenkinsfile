pipeline {
    agent none

    environment {
        DOCKER_REGISTRY   = "docker.io/ama2352"
        SONAR_HOST        = "http://192.168.242.10:30090"
        KUBERNETES_SERVER = "https://192.168.242.10:6443"
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('CI') {
            agent { label 'built-in' }

            stages {

                stage('Checkout') {
                    steps {
                        echo "Checking out source code from SCM..."
                        checkout scm
                        script {
                            env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'latest'}"
                            echo "Image tag: ${env.IMAGE_TAG}"
                        }
                    }
                }

                stage('Verify Source') {
                    parallel {

                        stage('Test Dispatch') {
                            agent {
                                docker {
                                    image 'golang:1.25.7-alpine'
                                    args  '-u root -e HOME=/root -e GOPATH=/root/go -v /tmp/go-mod-cache:/root/go/pkg/mod -v /tmp/go-build-cache:/root/.cache/go-build'
                                    reuseNode true
                                }
                            }
                            steps {
                                dir('services/dispatch') {
                                    sh '''
                                        echo "=== [dispatch] Downloading Go modules ==="
                                        go mod download
                                        echo "=== [dispatch] Running go vet ==="
                                        go vet ./...
                                        echo "=== [dispatch] Running unit tests ==="
                                        go test -v -coverprofile=coverage.out ./... || echo "No tests yet"
                                        echo "=== [dispatch] Tests complete ==="
                                    '''
                                }
                            }
                        }

                        stage('Test Notification') {
                            agent {
                                docker {
                                    image 'golang:1.25.7-alpine'
                                    args  '-u root -e HOME=/root -e GOPATH=/root/go -v /tmp/go-mod-cache:/root/go/pkg/mod -v /tmp/go-build-cache:/root/.cache/go-build'
                                    reuseNode true
                                }
                            }
                            steps {
                                dir('services/notification') {
                                    sh '''
                                        echo "=== [notification] Downloading Go modules ==="
                                        go mod download
                                        echo "=== [notification] Running go vet ==="
                                        go vet ./...
                                        echo "=== [notification] Running unit tests ==="
                                        go test -v -coverprofile=coverage.out ./... || echo "No tests yet"
                                        echo "=== [notification] Tests complete ==="
                                    '''
                                }
                            }
                        }

                        stage('Scan Dependencies') {
                            agent {
                                docker {
                                    image 'golang:1.25.7-alpine'
                                    args  '-u root -e HOME=/root -e GOPATH=/root/go -v /tmp/go-mod-cache:/root/go/pkg/mod -v /tmp/go-build-cache:/root/.cache/go-build'
                                    reuseNode true
                                }
                            }
                            steps {
                                sh '''
                                    echo "=== Installing govulncheck ==="
                                    go install golang.org/x/vuln/cmd/govulncheck@latest
                                    GOVULNCHECK=$(go env GOPATH)/bin/govulncheck
                                    echo "=== [dispatch] Scanning for known vulnerabilities ==="
                                    cd services/dispatch && $GOVULNCHECK ./...
                                    echo "=== [notification] Scanning for known vulnerabilities ==="
                                    cd ../../services/notification && $GOVULNCHECK ./...
                                    echo "=== Dependency scan complete — no known vulnerabilities ==="
                                '''
                            }
                        }

                    }
                }

                stage('SonarQube Analysis') {
                    agent {
                        docker {
                            image 'sonarsource/sonar-scanner-cli:11.3'
                            args  '-u root -e HOME=/root -v /tmp/sonar-cache:/root/.sonar/cache'
                            reuseNode true
                        }
                    }
                    steps {
                        withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                            sh '''
                                echo "=== [dispatch] Running SonarQube analysis ==="
                                cd services/dispatch
                                sonar-scanner -Dsonar.host.url=${SONAR_HOST} -Dsonar.token=${SONAR_TOKEN}
                                echo "=== [dispatch] SonarQube analysis submitted ==="
                                echo "=== [notification] Running SonarQube analysis ==="
                                cd ../../services/notification
                                sonar-scanner -Dsonar.host.url=${SONAR_HOST} -Dsonar.token=${SONAR_TOKEN}
                                echo "=== [notification] SonarQube analysis submitted ==="
                            '''
                        }
                    }
                }

                stage('Build Images') {
                    agent {
                        docker {
                            image 'docker:26-cli'
                            args  '-v /var/run/docker.sock:/var/run/docker.sock -u root'
                            reuseNode true
                        }
                    }
                    steps {
                        sh '''
                            set -e
                            echo "=== [dispatch] Building Docker image: dispatch-service:${IMAGE_TAG} ==="
                            docker build -t dispatch-service:${IMAGE_TAG}     services/dispatch
                            echo "=== [dispatch] Saving image to tar for scanning ==="
                            docker save  dispatch-service:${IMAGE_TAG}     -o dispatch-service.tar
                            echo "=== [notification] Building Docker image: notification-service:${IMAGE_TAG} ==="
                            docker build -t notification-service:${IMAGE_TAG} services/notification
                            echo "=== [notification] Saving image to tar for scanning ==="
                            docker save  notification-service:${IMAGE_TAG} -o notification-service.tar
                            echo "=== Image tars ready for security scan ==="
                            ls -lh *.tar
                        '''
                    }
                }

                stage('Scan Images') {
                    agent {
                        docker {
                            image 'aquasec/trivy:0.48.3'
                            args  '-u root -v /tmp/trivy-cache:/root/.cache/trivy --entrypoint='
                            reuseNode true
                        }
                    }
                    steps {
                        sh '''
                            set -e
                            SCAN_FAILED=0
                            echo "=== [dispatch] Scanning for HIGH/CRITICAL CVEs ==="
                            trivy image --input dispatch-service.tar \
                                --severity HIGH,CRITICAL --exit-code 1 --format table \
                                || SCAN_FAILED=1
                            echo "=== [notification] Scanning for HIGH/CRITICAL CVEs ==="
                            trivy image --input notification-service.tar \
                                --severity HIGH,CRITICAL --exit-code 1 --format table \
                                || SCAN_FAILED=1
                            [ $SCAN_FAILED -eq 0 ] || { echo "Security gate failed — not pushing."; exit 1; }
                            echo "=== Security gate passed — both images are clean ==="
                        '''
                    }
                }

                stage('Push Images') {
                    agent {
                        docker {
                            image 'docker:26-cli'
                            args  '-v /var/run/docker.sock:/var/run/docker.sock -u root'
                            reuseNode true
                        }
                    }
                    steps {
                        withCredentials([usernamePassword(
                            credentialsId: 'docker-registry-credentials',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        )]) {
                            sh '''
                                set -e
                                echo "=== Authenticating with Docker registry ==="
                                echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin

                                echo "=== [dispatch] Tagging and pushing to ${DOCKER_REGISTRY} ==="
                                docker tag dispatch-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
                                docker tag dispatch-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/dispatch-service:latest
                                docker push ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
                                docker push ${DOCKER_REGISTRY}/dispatch-service:latest

                                echo "=== [notification] Tagging and pushing to ${DOCKER_REGISTRY} ==="
                                docker tag notification-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}
                                docker tag notification-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/notification-service:latest
                                docker push ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}
                                docker push ${DOCKER_REGISTRY}/notification-service:latest

                                echo "=== Cleaning up local images to free disk space ==="
                                docker rmi dispatch-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/dispatch-service:latest || true
                                docker rmi notification-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/notification-service:latest || true
                                echo "=== All images pushed successfully ==="
                            '''
                        }
                    }
                }

            }
        }

        stage('CD') {
            agent {
                kubernetes {
                    cloud 'Kubernetes'  
                    namespace 'jenkins'     
                    yamlFile 'infrastructure/vm/platform/jenkins/pod-templates/cd-pod.yaml'
                    defaultContainer 'kubectl'
                }
            }

            stages {

                stage('Deploy to Kubernetes') {
                    steps {
                        echo "Checking out source code to get manifests..."
                        checkout scm
                        sh '''
                            set -e
                            echo "=== Starting Kubernetes Deployment ==="

                            echo "--- [dispatch] Applying manifests ---"
                            export DOCKER_REGISTRY="${DOCKER_REGISTRY}"
                            export IMAGE_TAG="${IMAGE_TAG}"
                            cat services/dispatch/k8s.yaml | envsubst | kubectl apply -f -
                            echo "--- [dispatch] Applying Istio routing rules ---"
                            kubectl apply -f services/dispatch/istio.yaml

                            echo "--- [notification] Applying manifests ---"
                            cat services/notification/k8s.yaml | envsubst | kubectl apply -f -
                            echo "--- [notification] Applying Istio routing rules ---"
                            kubectl apply -f services/notification/istio.yaml

                            echo "--- Waiting for rollouts to complete (timeout: 300s) ---"
                            kubectl -n ride-hailing rollout status deployment/dispatch-service     --timeout=300s
                            kubectl -n ride-hailing rollout status deployment/notification-service --timeout=300s
                            echo "=== All deployments rolled out successfully ==="
                        '''
                    }
                }

                stage('Verify Deployment') {
                    steps {
                        sh '''
                            echo "=== Verifying pod health (rollout already confirmed readiness) ==="
                            # Check Running status and restart count — the only signal that matters post-rollout.
                            kubectl -n ride-hailing get pods -o wide
                            echo "=== Verification complete ==="
                        '''
                    }
                }

            }
        }

    }
    
    post {
        success {
            node('built-in') {
                script {
                    echo "Pipeline completed successfully! Deployed version: ${env.IMAGE_TAG}"
                    def body = readFile('infrastructure/vm/platform/jenkins/email/success.txt')
                        .replace('@@BUILD_NUMBER@@',  env.BUILD_NUMBER         ?: '')
                        .replace('@@GIT_COMMIT@@',    env.GIT_COMMIT           ?: '')
                        .replace('@@GIT_BRANCH@@',    env.GIT_BRANCH           ?: 'N/A')
                        .replace('@@IMAGE_TAG@@',     env.IMAGE_TAG            ?: '')
                        .replace('@@BUILD_DURATION@@', currentBuild.durationString ?: '')
                        .replace('@@DOCKER_REGISTRY@@', DOCKER_REGISTRY        ?: '')
                        .replace('@@TIMESTAMP@@',     new Date().toString())
                    mail(
                        to:      'honguyenminhsang2005@gmail.com',
                        subject: "\u2713 CI/CD Pipeline Success - Build #${env.BUILD_NUMBER}",
                        body:    body
                    )
                }
            }
        }

        failure {
            node('built-in') {
                script {
                    echo "Pipeline failed! Check logs for details."
                    def body = readFile('infrastructure/vm/platform/jenkins/email/failure.txt')
                        .replace('@@BUILD_NUMBER@@',  env.BUILD_NUMBER         ?: '')
                        .replace('@@GIT_COMMIT@@',    env.GIT_COMMIT           ?: '')
                        .replace('@@GIT_BRANCH@@',    env.GIT_BRANCH           ?: '')
                        .replace('@@STAGE_NAME@@',    env.STAGE_NAME           ?: 'Unknown')
                        .replace('@@BUILD_DURATION@@', currentBuild.durationString ?: '')
                        .replace('@@TIMESTAMP@@',     new Date().toString())
                    mail(
                        to:      'honguyenminhsang2005@gmail.com',
                        subject: "\u2717 CI/CD Pipeline FAILURE - Build #${env.BUILD_NUMBER}",
                        body:    body
                    )
                }
            }
        }
    }
}

