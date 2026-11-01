pipeline {
    agent any

    parameters {
        string(
            name: 'TARGET_USER', 
            defaultValue: "${env.DEPLOY_USER ?: 'ubuntu'}", 
            description: 'Target system username for deployment'
        )
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        DEPLOY_TARGET_USER = "${params.TARGET_USER}"
        NODE_IMAGE         = 'node:18'
        DOTNET_IMAGE       = 'mcr.microsoft.com/dotnet/sdk:6.0'
        
        REGISTRY           = 'ghcr.io'
        CREDENTIALS_ID     = 'github-credentials' 
        
        IMAGE_BACKEND      = "ghcr.io/yaremyndaryna/streetcode-backend"
        IMAGE_FRONTEND     = "ghcr.io/yaremyndaryna/streetcode-frontend"
        
        KUBECONFIG_PATH    = '/etc/rancher/k3s/k3s.yaml'
        APP_URL            = 'http://localhost'
    }

    stages {
        stage('Check GitHub Security Status') {
            steps {
                script {
                    echo "Checking GitHub Actions (SonarCloud, Snyk & Trivy) status for commit: ${env.GIT_COMMIT}..."
                    
                    def response = sh(
                        script: "curl -s -H 'Accept: application/vnd.github+json' https://api.github.com/repos/yaremyndaryna/streetcode-devops/commits/${env.GIT_COMMIT}/check-runs",
                        returnStdout: true
                    )

                    if (!response.contains('"conclusion": "success"')) {
                        error("❌ GitHub CI/CD security checks failed or are pending! Aborting deployment.")
                    } else {
                        echo "✅ Security checks passed successfully."
                    }
                }
            }
        }

        stage('Run Unit Tests') {
            parallel {
                stage('Backend Unit Tests') {
                    steps {
                        echo 'Running .NET Unit Tests...'
                        sh """
                            docker run --rm \
                                -v \${WORKSPACE}:/app \
                                -w /app \
                                ${env.DOTNET_IMAGE} \
                                dotnet test apps/backend/Streetcode/Streetcode.XUnitTest/Streetcode.XUnitTest.csproj --configuration Release
                        """
                    }
                }
                stage('Frontend Unit Tests') {
                    steps {
                        echo 'Running Frontend Unit Tests...'
                        sh """
                            docker run --rm \
                                -v \${WORKSPACE}:/app \
                                -w /app/apps/frontend \
                                ${env.NODE_IMAGE} \
                                npm run --if-present test -- --watchAll=false --passWithNoTests
                        """
                    }
                }
            }
        }

        stage('Build Docker Images') {
            environment {
                DOCKER_BUILDKIT = '1'
            }
            steps {
                script {
                    echo "Building Docker images with BuildKit enabled..."
                    sh "docker build -t ${IMAGE_BACKEND}:${env.BUILD_NUMBER} ./apps/backend"
                    sh "docker build -t ${IMAGE_FRONTEND}:${env.BUILD_NUMBER} ./apps/frontend"
                    
                    sh "docker tag ${IMAGE_BACKEND}:${env.BUILD_NUMBER} ${IMAGE_BACKEND}:latest"
                    sh "docker tag ${IMAGE_FRONTEND}:${env.BUILD_NUMBER} ${IMAGE_FRONTEND}:latest"
                }
            }
        }

        stage('Push Artifacts to GHCR') {
            steps {
                withCredentials([usernamePassword(credentialsId: env.CREDENTIALS_ID, usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    sh """
                        echo "Logging in to GitHub Container Registry..."
                        echo \$GH_TOKEN | docker login ghcr.io -u \$GH_USER --password-stdin

                        echo "Pushing Backend images..."
                        docker push ${IMAGE_BACKEND}:${env.BUILD_NUMBER}
                        docker push ${IMAGE_BACKEND}:latest

                        echo "Pushing Frontend images..."
                        docker push ${IMAGE_FRONTEND}:${env.BUILD_NUMBER}
                        docker push ${IMAGE_FRONTEND}:latest
                    """
                }
            }
        }

        stage('Deploy to K3s') {
            steps {
                script {
                    echo "Applying Kubernetes Manifests..."
                    sh """
                        export KUBECONFIG=${env.KUBECONFIG_PATH}
                        
                        kubectl apply -f k8s/app/namespace.yaml
                        kubectl apply -f k8s/app/secrets.yaml
                        kubectl apply -f k8s/app/configmap.yaml
                        kubectl apply -f k8s/app/

                        kubectl set image deployment/backend backend=${IMAGE_BACKEND}:${env.BUILD_NUMBER} -n streetcode
                        kubectl set image deployment/frontend frontend=${IMAGE_FRONTEND}:${env.BUILD_NUMBER} -n streetcode
                    """
                }
            }
        }

        stage('Verify Rollout Status') {
            steps {
                script {
                    echo "Checking Deployment Rollout..."
                    sh """
                        export KUBECONFIG=${env.KUBECONFIG_PATH}
                        
                        kubectl rollout status deployment/backend -n streetcode --timeout=120s
                        kubectl rollout status deployment/frontend -n streetcode --timeout=120s
                        
                        kubectl get pods -n streetcode
                    """
                }
            }
        }

        stage('Smoke Test') {
            steps {
                script {
                    echo 'Verifying application accessibility via Traefik Ingress...'
                    sh """
                        sleep 5
                        echo "1. Checking Frontend access..."
                        curl -fsS --retry 10 --retry-delay 3 ${env.APP_URL}/ > /dev/null && echo "✅ Frontend is live!"

                        echo "2. Checking Backend API access..."
                        curl -fsS --retry 10 --retry-delay 3 ${env.APP_URL}/api > /dev/null && echo "✅ Backend API is live!"
                    """
                }
            }
        }
    }

    post {
        always {
            sh 'chown -R $(id -u):$(id -g) ${WORKSPACE} || true'
            sh 'docker logout ghcr.io || true'
        }
        success {
            echo '✅ Pipeline succeeded: Infrastructure verified, Images pushed, K3s deployed successfully!'
        }
        failure {
            echo '❌ Pipeline failed!'
        }
    }
}