pipeline {
    agent any

    parameters {
        string(
            name: 'TARGET_USER', 
            defaultValue: 'ubuntu', 
            description: 'Target system username for Ansible deployment'
        )
        string(
            name: 'BRANCH_NAME', 
            defaultValue: 'jenkins', 
            description: 'Git branch to deploy'
        )
    }

    environment {
        DEPLOY_USER = "${params.TARGET_USER}"
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: "${params.BRANCH_NAME}", 
                    url: 'https://github.com/yaremyndaryna/streetcode-devops.git'
            }
        }

        stage('Run Backend Tests') {
            steps {
                echo 'Running all .NET tests via solution file...'
                sh 'dotnet test apps/backend/Streetcode/Streetcode.sln --configuration Release'
            }
        }

        stage('Run Frontend Tests') {
            steps {
                echo 'Running Frontend Tests...'
                dir('apps/frontend') {
                    sh 'npm test -- --watchAll=false --passWithNoTests'
                }
            }
        }

        stage('Deploy via Ansible') {
            steps {
                echo "Deploying Streetcode application for target user: ${env.DEPLOY_USER}"
                
                sh "ansible-playbook site.yml -e 'target_user=${env.DEPLOY_USER}'"
            }
        }
    }

    post {
        success {
            echo "✅ All tests passed and application deployed successfully!"
        }
        failure {
            echo "❌ Tests or deployment failed."
        }
    }
}