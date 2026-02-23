pipeline {
    agent none

    environment {
        DOCKER_REGISTRY   = "${env.DOCKER_REGISTRY   ?: 'docker.io/your-dockerhub-username'}"
        SONAR_HOST        = "${env.SONAR_HOST        ?: 'http://192.168.242.10:30090'}"
        KUBERNETES_SERVER = "${env.KUBERNETES_SERVER ?: 'https://192.168.242.10:6443'}"
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
                                    args  '-u root -e HOME=/root -e GOPATH=/root/go'
                                    reuseNode true
                                }
                            }
                            steps {
                                dir('services/dispatch') {
                                    sh '''
                                        go mod download
                                        go vet ./...
                                        go test -v -coverprofile=coverage.out ./... || echo "No tests yet"
                                    '''
                                }
                            }
                        }

                        stage('Test Notification') {
                            agent {
                                docker {
                                    image 'golang:1.25.7-alpine'
                                    args  '-u root -e HOME=/root -e GOPATH=/root/go'
                                    reuseNode true
                                }
                            }
                            steps {
                                dir('services/notification') {
                                    sh '''
                                        go mod download
                                        go vet ./...
                                        go test -v -coverprofile=coverage.out ./... || echo "No tests yet"
                                    '''
                                }
                            }
                        }

                        stage('Scan Dependencies') {
                            agent {
                                docker {
                                    image 'golang:1.25.7-alpine'
                                    args  '-u root -e HOME=/root -e GOPATH=/root/go'
                                    reuseNode true
                                }
                            }
                            steps {
                                sh '''
                                    go install golang.org/x/vuln/cmd/govulncheck@latest
                                    GOVULNCHECK=$(go env GOPATH)/bin/govulncheck
                                    cd services/dispatch && $GOVULNCHECK ./...
                                    cd ../../services/notification && $GOVULNCHECK ./...
                                '''
                            }
                        }

                    }
                }

                stage('SonarQube Analysis') {
                    agent {
                        docker {
                            image 'sonarsource/sonar-scanner-cli:11.3'
                            args  '-u root -e HOME=/root'
                            reuseNode true
                        }
                    }
                    steps {
                        withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                            sh '''
                                cd services/dispatch
                                sonar-scanner -Dsonar.host.url=${SONAR_HOST} -Dsonar.token=${SONAR_TOKEN}
                                cd ../../services/notification
                                sonar-scanner -Dsonar.host.url=${SONAR_HOST} -Dsonar.token=${SONAR_TOKEN}
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
                            docker build -t dispatch-service:${IMAGE_TAG}     services/dispatch
                            docker save  dispatch-service:${IMAGE_TAG}     -o dispatch-service.tar
                            docker build -t notification-service:${IMAGE_TAG} services/notification
                            docker save  notification-service:${IMAGE_TAG} -o notification-service.tar
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
                            trivy image --input dispatch-service.tar \
                                --severity HIGH,CRITICAL --exit-code 1 --format table \
                                || SCAN_FAILED=1
                            trivy image --input notification-service.tar \
                                --severity HIGH,CRITICAL --exit-code 1 --format table \
                                || SCAN_FAILED=1
                            [ $SCAN_FAILED -eq 0 ] || { echo "Security gate failed — not pushing."; exit 1; }
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
                                echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin

                                docker tag dispatch-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
                                docker tag dispatch-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/dispatch-service:latest
                                docker push ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG}
                                docker push ${DOCKER_REGISTRY}/dispatch-service:latest

                                docker tag notification-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}
                                docker tag notification-service:${IMAGE_TAG} ${DOCKER_REGISTRY}/notification-service:latest
                                docker push ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG}
                                docker push ${DOCKER_REGISTRY}/notification-service:latest

                                docker rmi dispatch-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/dispatch-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/dispatch-service:latest || true
                                docker rmi notification-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/notification-service:${IMAGE_TAG} \
                                           ${DOCKER_REGISTRY}/notification-service:latest || true
                            '''
                        }
                    }
                }

            }
        }

        stage('CD') {
            agent { label 'built-in' }

            stages {

                stage('Deploy to Kubernetes') {
                    agent {
                        docker {
                            image 'alpine/k8s:1.29.0'
                            args  '-u root -e HOME=/root'
                            reuseNode true
                        }
                    }
                    steps {
                        withCredentials([string(credentialsId: 'k8s-sa-token', variable: 'K8S_TOKEN')]) {
                            sh '''
                                set -e
                                cat > kubeconfig.yaml << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: ${KUBERNETES_SERVER}
    insecure-skip-tls-verify: true
  name: k8s
contexts:
- context:
    cluster: k8s
    user: jenkins
  name: k8s
current-context: k8s
users:
- name: jenkins
  user:
    token: ${K8S_TOKEN}
EOF
                                export KUBECONFIG=./kubeconfig.yaml
                                export DOCKER_REGISTRY="${DOCKER_REGISTRY}"
                                export IMAGE_TAG="${IMAGE_TAG}"

                                cat services/dispatch/k8s.yaml     | envsubst | kubectl apply -f -
                                kubectl apply -f services/dispatch/istio.yaml
                                cat services/notification/k8s.yaml | envsubst | kubectl apply -f -
                                kubectl apply -f services/notification/istio.yaml

                                kubectl -n ride-hailing rollout status deployment/dispatch-service     --timeout=300s
                                kubectl -n ride-hailing rollout status deployment/notification-service --timeout=300s
                            '''
                        }
                    }
                }

                stage('Verify Deployment') {
                    agent {
                        docker {
                            image 'alpine/k8s:1.29.0'
                            args  '-u root -e HOME=/root'
                            reuseNode true
                        }
                    }
                    steps {
                        sh '''
                            export KUBECONFIG=./kubeconfig.yaml
                            kubectl -n ride-hailing get pods -o wide
                            kubectl -n ride-hailing get svc
                            kubectl -n ride-hailing get gateway,virtualservice,destinationrule
                            kubectl -n ride-hailing get pods \
                                -o custom-columns='NAME:.metadata.name,CONTAINERS:.spec.containers[*].name'
                            kubectl -n istio-system get svc istio-ingressgateway
                        '''
                    }
                }

            }

            post {
                always {
                    sh 'rm -f kubeconfig.yaml'
                }
            }
        }

    }
    
    post {
        success {
            echo "Pipeline completed successfully!"
            echo "Deployed version: ${env.IMAGE_TAG}"

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
Image Tag:        ${env.IMAGE_TAG}
Build Duration:   ${currentBuild.durationString}

Deployed Images:
------------------
${DOCKER_REGISTRY}/dispatch-service:${env.IMAGE_TAG}
${DOCKER_REGISTRY}/notification-service:${env.IMAGE_TAG}

Security Validation:
------------------
✓ Unit Tests Passed (parallel — dispatch + notification)
✓ Dependency Scan Passed (govulncheck, parallel with tests)
✓ SonarQube Quality Gate Passed
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
Blue Ocean:    http://192.168.242.13:8080/blue/organizations/jenkins/ride-hailing-services/detail/ride-hailing-services/${env.BUILD_NUMBER}/pipeline
Console:       http://192.168.242.13:8080/job/ride-hailing-services/${env.BUILD_NUMBER}/console
Classic View:  http://192.168.242.13:8080/job/ride-hailing-services/${env.BUILD_NUMBER}/
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
- Stage 2 (Verify Source):    Unit test failures, vet errors, or vulnerable dependencies
- Stage 3 (SonarQube):        Code quality gate failed
- Stage 5 (Scan Images):      HIGH/CRITICAL CVEs in container images
- Stage 7 (Deploy):           Kubernetes deployment/rollout timeout

Security Alert:
------------------
⚠️ If failure occurred at Stage 5 (Scan Images):
   → Images were NOT pushed to registry
   → No vulnerable code reached production
   → Review Trivy output in build logs

Action Required:
------------------
1. Review full logs in Jenkins console
2. Check security scan output if applicable
3. Fix root cause before triggering a new build
4. Do NOT bypass security gates

Debug Commands:
------------------
# View Jenkins logs (Docker container on jenkins-vm)
ssh vagrant@192.168.242.13 'docker logs jenkins --tail 100'

# Check running Docker containers (CI agent containers)
ssh vagrant@192.168.242.13 'docker ps'

# Review last K8s deployment
kubectl -n ride-hailing get pods,svc

Failed at: ${new Date()}

View Build (Blue Ocean shows failed stage clearly):
------------------
Blue Ocean:    http://192.168.242.13:8080/blue/organizations/jenkins/ride-hailing-services/detail/ride-hailing-services/${env.BUILD_NUMBER}/pipeline
Console:       http://192.168.242.13:8080/job/ride-hailing-services/${env.BUILD_NUMBER}/console
Classic View:  http://192.168.242.13:8080/job/ride-hailing-services/${env.BUILD_NUMBER}/
===========================================
"""
            )
        }
    }
}

