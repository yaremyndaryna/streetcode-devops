@NonCPS
def parseChecks(String json) {
    def data = new groovy.json.JsonSlurperClassic().parseText(json)
    def runs = data.check_runs ?: []
    return [
        total  : runs.size(),
        names  : runs.collect { it.name.toLowerCase() },
        pending: runs.findAll { it.status != 'completed' }.collect { it.name },
        failed : runs.findAll {
            it.status == 'completed' && !(it.conclusion in ['success', 'neutral', 'skipped'])
        }.collect { it.name }
    ]
}

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        NODE_IMAGE      = 'node:18'
        DOTNET_IMAGE    = 'mcr.microsoft.com/dotnet/sdk:6.0'

        CREDENTIALS_ID  = 'github-credentials'
        IMAGE_BACKEND   = 'ghcr.io/yaremyndaryna/streetcode-backend'
        IMAGE_FRONTEND  = 'ghcr.io/yaremyndaryna/streetcode-frontend'

        KUBECONFIG_PATH = '/etc/rancher/k3s/k3s.yaml'
        APP_URL         = 'http://localhost'
    }

    stages {
        stage('Check GitHub Security & Build Status') {
            options { timeout(time: 20, unit: 'MINUTES') }
            steps {
                withCredentials([usernamePassword(credentialsId: env.CREDENTIALS_ID, usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    script {
                        env.IMAGE_TAG = env.GIT_COMMIT
                        def required = ['build, analyze & security scan', 'build, push & trivy scan']

                        echo "Waiting for GitHub checks on commit ${env.GIT_COMMIT}..."
                        waitUntil(initialRecurrencePeriod: 15000) {
                            def json = sh(
                                returnStdout: true,
                                script: 'curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/yaremyndaryna/streetcode-devops/commits/$GIT_COMMIT/check-runs?per_page=100"'
                            )
                            if (!json?.trim()) { return false }

                            def r = parseChecks(json)
                            if (r.failed) {
                                error("❌ GitHub checks failed: ${r.failed.join(', ')}")
                            }
                            def missing = required.findAll { k -> !r.names.any { it.contains(k) } }
                            if (r.pending || missing) {
                                echo "⏳ Pending: ${r.pending}, not started yet: ${missing}"
                                return false
                            }
                            return true
                        }
                        echo '✅ All required GitHub checks completed successfully (scans executed, images built and pushed).'
                    }
                }
            }
        }

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

        stage('Verify Images in GHCR') {
            steps {
                withCredentials([usernamePassword(credentialsId: env.CREDENTIALS_ID, usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    sh '''
                        echo "$GH_TOKEN" | docker login ghcr.io -u "$GH_USER" --password-stdin
                        docker manifest inspect "$IMAGE_BACKEND:$IMAGE_TAG"  > /dev/null && echo "✅ Backend image found"
                        docker manifest inspect "$IMAGE_FRONTEND:$IMAGE_TAG" > /dev/null && echo "✅ Frontend image found"
                    '''
                }
            }
        }

        stage('Deploy to K3s') {
            steps {
                script {
                    echo "Applying Kubernetes manifests, image tag ${env.IMAGE_TAG}..."
                    sh """
                        export KUBECONFIG=${env.KUBECONFIG_PATH}

                        kubectl apply -f k8s/app/namespace.yaml
                        kubectl apply -f k8s/app/secrets.yaml
                        kubectl apply -f k8s/app/configmap.yaml
                        kubectl apply -f k8s/app/

                        kubectl set image deployment/backend  backend=${env.IMAGE_BACKEND}:${env.IMAGE_TAG}  -n streetcode
                        kubectl set image deployment/frontend frontend=${env.IMAGE_FRONTEND}:${env.IMAGE_TAG} -n streetcode
                    """
                    env.DEPLOYED = 'true'
                }
            }
        }

        stage('Verify Rollout Status') {
            steps {
                sh """
                    export KUBECONFIG=${env.KUBECONFIG_PATH}

                    kubectl rollout status deployment/backend  -n streetcode --timeout=300s
                    kubectl rollout status deployment/frontend -n streetcode --timeout=300s

                    kubectl get pods -n streetcode
                """
            }
        }

        stage('Smoke Test') {
            steps {
                sh """
                    sleep 5
                    echo "1. Checking Frontend access..."
                    curl -fsS --retry 10 --retry-delay 3 ${env.APP_URL}/ > /dev/null && echo "✅ Frontend is live!"

                    echo "2. Checking Backend API access..."
                    curl -fsS --retry 10 --retry-delay 3 ${env.APP_URL}/api > /dev/null && echo "✅ Backend API is live!"
                """
            }
        }

        stage('Promote :latest') {
            steps {
                sh '''
                    for IMG in "$IMAGE_BACKEND" "$IMAGE_FRONTEND"; do
                        docker pull "$IMG:$IMAGE_TAG"
                        docker tag  "$IMG:$IMAGE_TAG" "$IMG:latest"
                        docker push "$IMG:latest"
                    done
                '''
            }
        }
    }

    post {
        always {
            sh 'chown -R $(id -u):$(id -g) ${WORKSPACE} || true'
            sh 'docker logout ghcr.io || true'
        }
        success {
            echo "✅ Pipeline succeeded: checks verified, images ${env.IMAGE_TAG} deployed to K3s and promoted to :latest."
        }
        failure {
            echo '❌ Pipeline failed!'
            script {
                if (env.DEPLOYED == 'true') {
                    echo 'Rolling back to the previous revision...'
                    sh '''
                        export KUBECONFIG=$KUBECONFIG_PATH
                        kubectl rollout undo deployment/backend  -n streetcode || true
                        kubectl rollout undo deployment/frontend -n streetcode || true
                    '''
                }
            }
        }
    }
}