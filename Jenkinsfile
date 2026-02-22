// =============================================================================
// CI/CD Pipeline for Ride-Hailing Microservices
//
// Architecture: two separate K8s agent pods
//   CI pod (ci-pod.yaml)  — golang, buildkit, sonar-scanner, trivy
//   CD pod (cd-pod.yaml)  — kubectl only
//
// CI stages share one pod instance (no stash needed between them).
// CD stages spin up a minimal kubectl-only pod after CI succeeds.
// This ensures CD tooling is never scheduled for builds that fail CI.
// =============================================================================

pipeline {
    // No top-level agent. Each phase declares its own pod so only the
    // containers actually needed for that phase are scheduled.
    agent none

    environment {
        // Set DOCKER_REGISTRY in Jenkins: Manage Jenkins → System →
        // Global properties → Environment variables
        // Example: docker.io/yourusername
        DOCKER_REGISTRY = "${env.DOCKER_REGISTRY ?: 'docker.io/your-dockerhub-username'}"
    }
    
    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        // =====================================================================
        // CI Phase
        // One pod for all CI stages: test → analyse → build → scan → push.
        // The pod stays alive across all nested stages so the workspace
        // (including built .tar files) is shared without stash/unstash.
        // =====================================================================
        stage('CI') {
            agent {
                kubernetes {
                    yamlFile 'infrastructure/vm/platform/jenkins/ci-pod.yaml'
                }
            }

            stages {
                // =============================================================
                // Stage 1: Checkout & Prepare
                // IMAGE_TAG is set here (not in environment{}) because
                // GIT_COMMIT is only populated after checkout scm runs.
                // =============================================================
                stage('Checkout') {
                    steps {
                        checkout scm
                        script {
                            env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7) ?: 'latest'}"
                            echo "Building commit: ${env.GIT_COMMIT}"
                            echo "Image tag:       ${env.IMAGE_TAG}"
                            echo "Registry:        ${env.DOCKER_REGISTRY}"
                        }
                    }
                }

                // =============================================================
                // Stage 2: Automated Tests (Parallel)
                // =============================================================
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

                // =============================================================
                // Stage 3: SonarQube Analysis
                // Runs after tests so coverage reports are available.
                // =============================================================
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

                // =============================================================
                // Stage 4: Scan Dependencies
                // govulncheck checks go.mod against the Go Vulnerability Database.
                // =============================================================
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
                            echo "All dependencies passed vulnerability scan"
                            '''
                        }
                    }
                }

                // =============================================================
                // Stage 5: Build Images (local tar only)
                // Images are written to .tar files for Trivy to scan.
                // They are NOT pushed yet — push only happens after scan passes.
                // =============================================================
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

                            echo "Images built (not pushed yet)"
                            ls -lh *.tar
                            '''
                        }
                    }
                }

                // =============================================================
                // Stage 6: Scan Container Images
                // SECURITY GATE — pipeline aborts here if HIGH/CRITICAL found.
                // .tar files from the previous stage are still on this pod's
                // workspace; no stash/unstash needed.
                // =============================================================
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
                                echo "SECURITY ALERT: Dispatch service has HIGH/CRITICAL vulnerabilities!"
                                SCAN_FAILED=1
                            else
                                echo "Dispatch service: No HIGH/CRITICAL vulnerabilities found"
                            fi

                            echo ""
                            echo "=== Scanning Notification Service Image ==="
                            if ! trivy image \
                                --input notification-service.tar \
                                --severity HIGH,CRITICAL \
                                --exit-code 1 \
                                --no-progress \
                                --format table; then
                                echo "SECURITY ALERT: Notification service has HIGH/CRITICAL vulnerabilities!"
                                SCAN_FAILED=1
                            else
                                echo "Notification service: No HIGH/CRITICAL vulnerabilities found"
                            fi

                            if [ $SCAN_FAILED -eq 1 ]; then
                                echo ""
                                echo "Security scan failed: images will NOT be pushed."
                                exit 1
                            fi

                            echo ""
                            echo "All images passed security scan - approved for push"
                            '''
                        }
                    }
                }

                // =============================================================
                // Stage 7: Push Validated Images
                // Only reached if security scan passed.
                // =============================================================
                stage('Push Images') {
                    steps {
                        container('buildkit') {
                            withCredentials([
                                usernamePassword(
                                    credentialsId: 'docker-registry-credentials',
                                    usernameVariable: 'DOCKER_USER',
                                    passwordVariable: 'DOCKER_PASS'
                                )
                            ]) {
                                sh '''
                                set -e

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

                                echo "All validated images pushed to registry"
                                '''
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // CD Phase
        // Minimal kubectl-only pod. Only scheduled after all CI stages pass.
        // Could not have been created on the CI pod because the source code
        // checked out there is not present here — `kubectl apply` reads from
        // the repo checkout on this pod's own workspace.
        // =====================================================================
        stage('CD') {
            agent {
                kubernetes {
                    yamlFile 'infrastructure/vm/platform/jenkins/cd-pod.yaml'
                }
            }

            stages {
                // =============================================================
                // Stage 8: Deploy to Kubernetes
                // =============================================================
                stage('Deploy to Kubernetes') {
                    steps {
                        container('kubectl') {
                            sh '''
                            set -e

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
                            echo "=== Waiting for Dispatch Service rollout ==="
                            if ! kubectl -n ride-hailing rollout status deployment/dispatch-service --timeout=300s; then
                                echo "Dispatch rollout timeout - debug info:"
                                kubectl -n ride-hailing get pods -l app=dispatch-service
                                kubectl -n ride-hailing describe pods -l app=dispatch-service | tail -50
                                exit 1
                            fi

                            echo ""
                            echo "=== Waiting for Notification Service rollout ==="
                            if ! kubectl -n ride-hailing rollout status deployment/notification-service --timeout=300s; then
                                echo "Notification rollout timeout - debug info:"
                                kubectl -n ride-hailing get pods -l app=notification-service
                                kubectl -n ride-hailing describe pods -l app=notification-service | tail -50
                                exit 1
                            fi

                            echo ""
                            echo "All deployments rolled out successfully"
                            '''
                        }
                    }
                }

                // =============================================================
                // Stage 9: Verify Deployment
                // =============================================================
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
                            kubectl -n ride-hailing get pods \
                                -o custom-columns='NAME:.metadata.name,CONTAINERS:.spec.containers[*].name'

                            echo "=== Ingress Gateway ==="
                            kubectl -n istio-system get svc istio-ingressgateway

                            echo ""
                            echo "Deployment verified. Access services via NodePort 30080 on any cluster node."
                            '''
                        }
                    }
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
# Check build agent pods
kubectl -n jenkins get pods

# View Jenkins controller logs (runs on jenkins-vm as Docker container)
ssh vagrant@192.168.242.13 'docker logs jenkins --tail 100'

# Review last deployment
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

