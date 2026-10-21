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
        stage('Check SonarCloud Status') {
            steps {
                script {
                    echo "Checking SonarCloud analysis status for commit: ${env.GIT_COMMIT}..."
                    
                    def response = sh(
                        script: "curl -s -H 'Accept: application/vnd.github+json' https://api.github.com/repos/yaremyndaryna/streetcode-devops/commits/${env.GIT_COMMIT}/check-runs",
                        returnStdout: true
                    )

                    if (!response.contains('"conclusion": "success"')) {
                        error("❌ SonarCloud analysis failed, is still running, or has not passed yet! Aborting Jenkins deployment.")
                    } else {
                        echo "✅ SonarCloud status verified successfully. Proceeding with tests and deployment..."
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
            echo '✅ Pipeline finished successfully: Tests passed and application deployed!'
        }
        failure {
            echo '❌ Pipeline failed.'
        }
    }
}