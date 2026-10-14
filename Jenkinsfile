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
        DOTNET_IMAGE       = 'mcr.microsoft.com/dotnet/sdk:8.0'
    }

    stages {
        stage('Run Tests') {
            parallel {
                stage('Backend Unit Tests') {
                    steps {
                        echo 'Running .NET Unit Tests...'
                        sh '''
                            docker run --rm \
                                -v ${WORKSPACE}:/app \
                                -w /app \
                                mcr.microsoft.com/dotnet/sdk:6.0 \
                                dotnet test apps/backend/Streetcode/Streetcode.XUnitTest/Streetcode.XUnitTest.csproj --configuration Release
                        '''
                    }
                }
                stage('Frontend Unit Tests') {
                    steps {
                        echo 'Running Frontend Unit Tests...'
                        sh '''
                            docker run --rm \
                                -v ${WORKSPACE}:/app \
                                -w /app/apps/frontend \
                                node:18 \
                                npm run --if-present test -- --watchAll=false --passWithNoTests
                        '''
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