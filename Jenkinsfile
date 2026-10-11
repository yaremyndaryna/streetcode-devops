pipeline {
    agent any

    options {
        skipDefaultCheckout(true)   // прибирає дубльований checkout
        timestamps()
    }

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
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "*/${params.BRANCH_NAME}"]],
                    userRemoteConfigs: [[url: 'https://github.com/yaremyndaryna/streetcode-devops.git']],
                    extensions: [
                        [$class: 'SubmoduleOption', recursiveSubmodules: true, parentCredentials: true],
                        [$class: 'CleanBeforeCheckout']
                    ]
                ])
            }
        }

        stage('Debug Workspace') {
            steps {
                echo 'Що є у workspace (Jenkins) та що бачить Docker:'
                sh '''
                    ls -la ${WORKSPACE}
                    echo "--- apps ---"
                    ls -la ${WORKSPACE}/apps || true
                    echo "--- .gitmodules ---"
                    cat ${WORKSPACE}/.gitmodules || echo "no .gitmodules"
                    echo "--- Docker mount check ---"
                    docker run --rm -v ${WORKSPACE}:/app alpine ls -la /app/apps || true
                '''
            }
        }

        stage('Run Backend Unit Tests') {
            steps {
                echo 'Running backend tests inside .NET container...'
                sh '''
                    docker run --rm -v ${WORKSPACE}:/app -w /app \
                    mcr.microsoft.com/dotnet/sdk:8.0 sh -c '
                        SLN=$(find . -name "*.sln" | head -n 1)
                        if [ -z "$SLN" ]; then
                            echo "ERROR: .sln file not found"
                            exit 1
                        fi
                        echo "Using solution: $SLN"
                        dotnet test "$SLN"
                    '
                '''
            }
        }

        stage('Run Frontend Tests') {
            steps {
                echo 'Running Frontend tests inside Node.js container...'
                sh '''
                    docker run --rm -v ${WORKSPACE}:/app -w /app node:18 sh -c '
                        PKG=$(find . -name package.json -not -path "*/node_modules/*" \
                              \\( -ipath "*front*" -o -ipath "*client*" \\) | head -n 1)
                        if [ -z "$PKG" ]; then
                            echo "ERROR: frontend package.json not found"
                            exit 1
                        fi
                        DIR=$(dirname "$PKG")
                        echo "Using frontend dir: $DIR"
                        cd "$DIR"
                        npm ci
                        npm test -- --watchAll=false --passWithNoTests
                    '
                '''
            }
        }

        stage('Deploy via Ansible') {
            steps {
                echo "Deploying Streetcode application for target user: ${params.TARGET_USER}"
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