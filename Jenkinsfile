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

    stages {
        stage('Checkout Code') {
            steps {
                git branch: "${params.BRANCH_NAME}", 
                    url: 'https://github.com/yaremyndaryna/streetcode-devops.git'
            }
        }

        stage('Run All Backend Tests') {
            steps {
                echo 'Running .NET tests inside Docker SDK container...'
                sh 'docker run --rm -v $(pwd):/app -w /app mcr.microsoft.com/dotnet/sdk:8.0 dotnet test apps/backend/Streetcode/Streetcode.sln --configuration Release'
            }
        }

        stage('Run Frontend Tests') {
            steps {
                echo 'Running Frontend tests inside Node.js container...'
                sh 'docker run --rm -v $(pwd):/app -w /app/apps/frontend node:18 npm test -- --watchAll=false --passWithNoTests'
            }
        }

        stage('Deploy via Ansible') {
            steps {
                echo "Deploying Streetcode application for target user: ${params.TARGET_USER}"
                // Передаємо інвентар -i inventory та використовуємо params.TARGET_USER напряму
                sh "ansible-playbook -i inventory site.yml -e 'target_user=${params.TARGET_USER}'"
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