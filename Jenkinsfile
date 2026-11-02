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

        KUBECONFIG_SRC  = '/etc/rancher/k3s/k3s.yaml'
        KUBECONFIG_PATH = '/var/jenkins_home/k3s.yaml'
        K3S_API         = 'https://host.docker.internal:6443'
        APP_URL         = 'http://host.docker.internal'
    }

    stages {
        stage('Check GitHub Security & Build Status') {
            options { timeout(time: 20, unit: 'MINUTES') }
            steps {
                withCredentials([usernamePassword(credentialsId: env.CREDENTIALS_ID, usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
                    script {
                        env.IMAGE_TAG = env.GIT_COMMIT
                        def required = ['Build, Analyze & Security Scan', 'Build, Push & Trivy Scan']

                        echo "Waiting for GitHub checks on commit ${env.GIT_COMMIT}..."
                        waitUntil(initialRecurrencePeriod: 15000) {
                            def failed  = []
                            def waiting = []
                            for (name in required) {
                                def state = ''
                                withEnv(["CHECK_NAME=${name}"]) {
                                    state = sh(returnStdout: true, script: '''#!/bin/sh
RESP=$(curl -s -G -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GH_TOKEN" --data-urlencode "check_name=$CHECK_NAME" --data-urlencode "filter=latest" "https://api.github.com/repos/yaremyndaryna/streetcode-devops/commits/$GIT_COMMIT/check-runs")
if echo "$RESP" | grep -q '"total_count": 0'; then
  echo missing
elif echo "$RESP" | grep -q '"status": "completed"'; then
  if echo "$RESP" | grep -Eq '"conclusion": "(success|neutral|skipped)"'; then echo success; else echo failed; fi
elif echo "$RESP" | grep -q '"total_count"'; then
  echo pending
else
  echo api_error
fi
''').trim()
                                }
                                echo "${name}: ${state}"
                                if (state == 'failed') {
                                    failed << name
                                } else if (state != 'success') {
                                    waiting << name
                                }
                            }
                            if (failed) {
                                error("❌ GitHub checks failed: ${failed}")
                            }
                            if (waiting) {
                                echo "⏳ Still waiting for: ${waiting}"
                                return false
                            }
                            return true
                        }
                        echo '✅ All required GitHub checks completed successfully.'
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

        stage('Prepare Kubeconfig') {
            steps {
                sh '''
                    cp "$KUBECONFIG_SRC" "$KUBECONFIG_PATH"
                    chmod 600 "$KUBECONFIG_PATH"
                    kubectl --kubeconfig "$KUBECONFIG_PATH" config set-cluster default \
                        --server="$K3S_API" --tls-server-name=kubernetes
                    kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes
                '''
            }
        }

        stage('Deploy to K3s') {
            steps {
                script {
                    sh '''
                        export KUBECONFIG=/var/jenkins_home/k3s.yaml
                        
                        kubectl apply -f k8s/app/namespace.yml
                        kubectl apply -f k8s/app/
                        
                        kubectl set image deployment/backend backend=${IMAGE_BACKEND}:${IMAGE_TAG} -n streetcode
                        kubectl set image deployment/frontend frontend=${IMAGE_FRONTEND}:${IMAGE_TAG} -n streetcode
                    '''
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