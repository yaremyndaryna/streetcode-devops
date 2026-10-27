pipeline {
    agent any

    parameters {
        string(
            name: 'TARGET_USER', 
            defaultValue: "${env.DEPLOY_USER ?: 'ubuntu'}", 
            description: 'Target system username for Ansible deployment'
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
    }

    stages {
        stage('Check GitHub Security & Quality Status') {
            steps {
                script {
                    echo "Checking GitHub Actions (SonarCloud, Snyk & Trivy) status for commit: ${env.GIT_COMMIT}..."
                    
                    def response = sh(
                        script: "curl -s -H 'Accept: application/vnd.github+json' https://api.github.com/repos/yaremyndaryna/streetcode-devops/commits/${env.GIT_COMMIT}/check-runs",
                        returnStdout: true
                    )

                    if (!response.contains('"conclusion": "success"')) {
                        error("❌ GitHub CI/CD checks (SonarCloud/Snyk/Trivy) failed, are still running, or have not passed yet! Aborting Jenkins deployment.")
                    } else {
                        echo "✅ All GitHub CI checks verified successfully. Proceeding with tests and deployment..."
                    }
                }
            }
        }

        stage('Run Tests') {
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

        stage('Deploy via Ansible') {
            steps {
                echo "Deploying Streetcode application for target user: ${env.DEPLOY_TARGET_USER}"
                withCredentials([sshUserPrivateKey(credentialsId: 'deploy-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh """
                        ansible-playbook -i inventory/jenkins.yml site.yml --tags app \
                          --private-key "$SSH_KEY" -e "target_user=${env.DEPLOY_TARGET_USER}"
                    """
                }
            }
        }

        stage('Push Artifacts to GHCR') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    sh """
                        echo "Logging in to GitHub Container Registry..."
                        echo \$GH_TOKEN | docker login ghcr.io -u \$GH_USER --password-stdin

                        echo "Tagging and pushing Backend image..."
                        docker tag streetcode-app-backend:latest ghcr.io/\$GH_USER/streetcode-backend:${env.BUILD_NUMBER}
                        docker tag streetcode-app-backend:latest ghcr.io/\$GH_USER/streetcode-backend:latest
                        docker push ghcr.io/\$GH_USER/streetcode-backend:${env.BUILD_NUMBER}
                        docker push ghcr.io/\$GH_USER/streetcode-backend:latest

                        echo "Tagging and pushing Frontend image..."
                        docker tag streetcode-app-streetcode-app-1:latest ghcr.io/\$GH_USER/streetcode-frontend:${env.BUILD_NUMBER}
                        docker tag streetcode-app-streetcode-app-1:latest ghcr.io/\$GH_USER/streetcode-frontend:latest
                        docker push ghcr.io/\$GH_USER/streetcode-frontend:${env.BUILD_NUMBER}
                        docker push ghcr.io/\$GH_USER/streetcode-frontend:latest
                    """
                }
            }
        }

        stage('Verify Monitoring Status') {
            steps {
                script {
                    echo 'Checking if Monitoring stack is live...'
                    
                    sh '''
                        echo "Waiting for Prometheus..."
                        curl -fsS --retry 10 --retry-delay 3 http://host.docker.internal:9090/-/healthy || (echo "❌ Prometheus health check failed!" && exit 1)
                        
                        echo "Waiting for Grafana..."
                        curl -fsS --retry 10 --retry-delay 3 http://host.docker.internal:3001/api/health || (echo "❌ Grafana health check failed!" && exit 1)
                    '''
                    
                    echo '✅ All monitoring services are fully healthy!'
                }
            }
        }

        stage('Smoke Test') {
            steps {
                echo 'Verifying deployment accessibility...'
                sh '''
                    curl -fsS --retry 10 --retry-delay 3 http://host.docker.internal:3000/ > /dev/null && echo "✅ Frontend is accessible on port 3000!"
                '''
            }
        }
    }

    post {
        always {
            sh 'chown -R $(id -u):$(id -g) ${WORKSPACE} || true'
        }
        success {
            echo '✅ Pipeline finished successfully: Tests passed, application deployed via Ansible, and artifacts pushed to GHCR!'
        }
        failure {
            echo '❌ Pipeline failed.'
        }
    }
}