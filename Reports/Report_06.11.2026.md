**Period:** 29.10.2026 – 06.11.2026

**Report date:** 06.11.2026

# Work Completion Report: Streetcode Infrastructure Deployment

## 1. Overview

A cloud infrastructure for the **Streetcode** project was designed and deployed on AWS using *Infrastructure as Code* (Terraform + Ansible) and automated CI/CD (GitHub Actions + Jenkins). The infrastructure is split across **two dedicated EC2 instances** to isolate application workloads from automation and monitoring tools.

| Component | Technology |
| --- | --- |
| Cloud platform | AWS EC2 |
| Provisioning | Terraform |
| Server configuration | Ansible |
| Container orchestration | K3s (lightweight Kubernetes) |
| CI (build, analysis, scanning) | GitHub Actions (SonarCloud, Snyk, Trivy) |
| CD (tests, deployment, checks) | Jenkins |
| Image registry | GitHub Container Registry (GHCR) |
| Monitoring | Prometheus, Grafana, Node Exporter, cAdvisor |

---

## 2. Architecture and Component Distribution

### 2.1 App Node (medium instance)

**Purpose:** hosts the production application and containerized microservices managed by K3s.

| Component | Description | Port |
| --- | --- | --- |
| Frontend | React application, 2 replicas managed by K3s, traffic routed via Ingress | 80 / 443 |
| Backend | .NET 6 Web API (REST + Swagger), exposed externally through Ingress at the `/swagger` path | 5000 (internal) |
| Database | Microsoft SQL Server with persistent volumes | 1433 (internal) |
| Cache | Redis | 6379 (internal) |
| Node Exporter | Host-level metrics (CPU, RAM, disk, network) for Prometheus | 9100 (inter-node only) |

### 2.2 Tools Node (small instance)

**Purpose:** continuous integration and delivery, deployment automation, and observability.

| Component | Container / service | Purpose | Port |
| --- | --- | --- | --- |
| Jenkins | `streetcode-jenkins` | Tests, deployment to K3s, smoke tests, image promotion | 8080 |
| Prometheus | `streetcode-prometheus` | Collects metrics from both nodes and containers | 9090 |
| Grafana | `streetcode-grafana` | Dashboards for visual monitoring | 3000 |
| Node Exporter | `streetcode-node-exporter-tools` | Metrics of the Tools Node itself | 9100 |
| cAdvisor | `streetcode-cadvisor-tools` | Docker container metrics on the Tools Node (Jenkins, Prometheus, Grafana) | 8082 |

### 2.3 Metrics Collection Scheme

- **Node Exporter** is installed on **both** instances, so Prometheus collects host-level metrics from the App Node and the Tools Node.
- **cAdvisor** runs on the Tools Node and exposes per-container resource usage metrics.
- Port `9100` is open only inside the Security Group (`self = true`), so metrics are not reachable from outside.

---

## 3. Completed Stages

### Stage 1. Infrastructure provisioning (Terraform)

1. Navigate to the `terraform/` directory.
2. Run `terraform init` and `terraform apply`.
3. Record the output public IP addresses of the App Node and the Tools Node.

### Stage 2. Server configuration (Ansible)

1. Update `inventory.ini` with the IP addresses obtained from Terraform.
2. Run the playbook:

```bash
ansible-playbook -i inventory.ini setup-infrastructure.yml
```

Result: Docker, K3s, Jenkins, Prometheus, Grafana, Node Exporter, and cAdvisor are installed and configured on the instances.

### Stage 3. CI on GitHub Actions (two workflows)

The original single workflow was **split into two independent ones**, each responsible for its own task. This simplifies maintenance, allows checks to run in parallel, and makes it clear which stage failed.

#### 3.1 Workflow "SonarCloud Code Analysis & Snyk Security"

- **Job:** `Build, Analyze & Security Scan`
- **Triggers:** push to the `main`, `jenkins`, `load-balancer`, and `cloud` branches; pull requests (opened, synchronize, reopened).
- **Steps:**
  1. Checkout (full history, `fetch-depth: 0`, required by SonarCloud).
  2. Install .NET SDK 6.0 and Node.js 18.
  3. Static analysis of the backend code with **SonarCloud** (`dotnet-sonarscanner begin` → build → `end`).
  4. Install frontend dependencies (`npm ci`).
  5. Dependency vulnerability scanning with **Snyk** for the backend (`.sln`) and the frontend (`package.json`), with a `high` severity threshold.
- **Note:** the Snyk steps use `continue-on-error: true`, so discovered vulnerabilities do not block the build and are informational only.

#### 3.2 Workflow "Build, Push & Scan Images"

- **Job:** `Build, Push & Trivy Scan`
- **Triggers:** push to the `cloud` branch and manual run (`workflow_dispatch`).
- **Permissions:** `contents: read`, `packages: write`.
- **Steps:**
  1. Checkout and Docker Buildx setup.
  2. Authentication to GHCR using `GITHUB_TOKEN`.
  3. Build and push the **backend** image tagged `:<commit SHA>`.
  4. Build and push the **frontend** image tagged `:<commit SHA>` (build-arg `API_URL=/api`).
  5. Scan the pushed images with **Trivy** (`HIGH,CRITICAL` severities, `ignore-unfixed: true`).
- **Optimization:** GitHub Actions build cache (`type=gha`) is used separately for backend and frontend.
- **Note:** `exit-code: '0'` means Trivy only reports vulnerabilities and does not stop the pipeline.

> Images are built and published by **GitHub Actions**, not by Jenkins. Jenkins only verifies that they exist in GHCR and deploys them.

### Stage 4. CD on Jenkins

**4.1 Initial access.** The administrator password was retrieved from the Jenkins Docker container via SSH. The initial setup was then completed through the web interface (`http://<TOOLS_NODE_IP>:8080`): installing suggested plugins and creating the administrator account.

**4.2 Credentials (Global credentials).** Four entries were added:

| ID | Type | Purpose |
| --- | --- | --- |
| `k3s-kubeconfig` | Secret file | kubeconfig of the K3s cluster from the App Node |
| `github-credentials` | Username with password | GitHub username and PAT (repository and package write scopes) |
| `app-node-ip` | Secret text | Public IP of the App Node |
| `tools-node-ip` | Secret text | Public IP of the Tools Node |

**4.3 Pipeline.** The `streetcode-pipeline` item (type *Pipeline*) was created: `Pipeline script from SCM`, Git, `github-credentials`, branch `*/cloud`, Script Path `Jenkinsfile`.

**4.4 Pipeline options:**

| Parameter | Value | Why |
| --- | --- | --- |
| `timestamps()` | enabled | Timestamps in logs |
| `disableConcurrentBuilds()` | enabled | Prevents parallel deployments |
| `timeout` | 40 minutes | Protection against hangs |
| `buildDiscarder` | 10 builds | Saves disk space on the small instance |

**4.5 Pipeline stages:**

| # | Stage | What it does |
| --- | --- | --- |
| 1 | **Check GitHub Security & Build Status** | Polls the commit's check-runs through the GitHub API (every 15 s, 20 min timeout) and waits for both required checks to succeed: `Build, Analyze & Security Scan` and `Build, Push & Trivy Scan`. If a check fails, the pipeline stops. The image tag is set to `GIT_COMMIT`. |
| 2 | **Backend Unit Tests** | `dotnet test` in an isolated `dotnet/sdk:6.0` container (xUnit project, Release configuration). |
| 3 | **Frontend Unit Tests** | `npm test` in a `node:18` container (`--watchAll=false --passWithNoTests`). |
| 4 | **Verify Images in GHCR** | Logs in to GHCR and runs `docker manifest inspect` for the backend and frontend images with the commit tag. Ensures the images were actually built. |
| 5 | **Deploy to K3s** | `kubectl apply` of the manifests from `k8s/app/` and `kubectl set image` for the `backend` and `frontend` Deployments. |
| 6 | **Verify Rollout Status** | `kubectl rollout status` (300 s timeout) for both Deployments and a listing of pods. |
| 7 | **Smoke Test** | `curl` with retries against the frontend home page and the backend `/swagger/index.html`. |
| 8 | **Verify Prometheus Scraping App Node** | Uses the Prometheus API to check that scrape targets are in the `up` state. This is an informational check: on failure a warning is printed and the build does not fail. |
| 9 | **Promote :latest** | Images with the commit tag are re-tagged as `:latest` and pushed. This runs only after successful verification. |

**4.6 Post-processing (`post`):**

- **always:** restore workspace ownership and run `docker logout ghcr.io`.
- **success:** message confirming successful deployment and `:latest` promotion.
- **failure:** if the deployment has already happened (`DEPLOYED == 'true'`), an **automatic rollback** is performed with `kubectl rollout undo` for backend and frontend.

### Stage 5. Verification and monitoring

- Frontend and Swagger: `http://<App-Node-IP>/swagger/index.html`
- Prometheus: `http://<Tools-Node-IP>:9090`
- Grafana: `http://<Tools-Node-IP>:3000`
- Cluster status: `kubectl get pods -n streetcode`

---

## 4. Overall CI/CD Flow

```
git push (cloud branch)
   │
   ├─► GitHub Actions #1: Sonar + Snyk ──────────┐
   ├─► GitHub Actions #2: Build/Push + Trivy ────┤
   │                                             ▼
   └─► Jenkins: waits for both checks to succeed
          → unit tests → verify images in GHCR
          → deploy to K3s → rollout status
          → smoke tests → Prometheus check
          → promote :latest
          (on failure after deployment: automatic rollback)
```

---

## 5. Security Analysis

### 5.1 Network isolation (Security Group in Terraform)

- **Database and cache isolation.** The `frontend`, `backend`, `redis`, and `mssql` services are of type `ClusterIP`. Ports `1433` (MS SQL) and `6379` (Redis) are absent from the `ingress` rules, so they are unreachable from outside.
- **Controlled entry point.** External traffic reaches the App Node only through `80` and `443` (Kubernetes Ingress).
- **Internal communication (`self = true`).** Ports `6443` (Kubernetes API) and `9100` (Node Exporter) are open only to nodes in the same Security Group.
- **CI/CD and monitoring tools (`8080`, `3000`, `9090`).** Currently open to `0.0.0.0/0`. This is only for a test environment, but for production they should be restricted to a specific CIDR or placed behind a VPN.

### 5.2 Secrets management (three layers)

| Layer | Contents | Purpose | Rule |
| --- | --- | --- | --- |
| Local secrets | `terraform.tfvars`, `.env`, `ansible/group_vars/all/` | Running `terraform apply` and `ansible-playbook` | Must be listed in `.gitignore` |
| GitHub Secrets | `SONAR_TOKEN`, `SNYK_TOKEN`, `GITHUB_TOKEN` | Running workflows in GitHub Actions | Available only inside Actions sandboxes |
| Jenkins Credentials | `github-credentials`, `k3s-kubeconfig`, node IP addresses | Deployment from the `Jenkinsfile` | Stored encrypted, masked as `****` in logs |

### 5.3 CI-level security

- Static code analysis (**SonarCloud**).
- Dependency scanning (**Snyk**) for backend and frontend.
- Container image scanning (**Trivy**) at HIGH/CRITICAL levels.
- Deployment cannot proceed until the required GitHub checks complete successfully.

### 5.4 Production recommendations

- Restrict ports `8080`, `3000`, `9090` by CIDR or VPN/bastion; enable HTTPS.
- Switch Trivy (`exit-code: '1'`) and Snyk (remove `continue-on-error`) to blocking mode for critical vulnerabilities.
- Refine the Prometheus check: filter targets by the specific `job`/`instance` of the App Node, since the current `grep` reacts to any target in the `up` state.


---

# 6. Scaling: Architecture Evolution for High Availability (HA)

> This section is theoretical: it describes possible future development of the infrastructure, not completed work.

If the project outgrows the current two-node setup, the architecture typically evolves through the following stages.

### Stage 1. Moving the database out

Move MS SQL Server from a local K3s pod to a managed cloud service (for example, **AWS RDS**) or to a separate dedicated DB node.

- Removes load from the App Node.
- Solves backup and disk scaling concerns.
- Enables Multi-AZ deployment and automatic failover.

### Stage 2. Traffic balancing

Add an **AWS Application Load Balancer (ALB)** in front of the App Node.

- Allows deploying several App nodes in the Kubernetes cluster instead of one when needed.
- Provides health checks and TLS termination.
- Removes users' dependence on a single public IP.

### Stage 3. Separating the tools

Split Jenkins and Prometheus/Grafana onto different virtual machines.

- Heavy builds will not affect continuous stability monitoring.
- Node Exporter and cAdvisor stay on each node, while Prometheus collects their metrics from a separate host.

### Additional directions

- **Horizontal pod scaling:** more backend replicas and a Horizontal Pod Autoscaler driven by metrics.
- **Multi-node K3s:** several server nodes for an HA control plane and agent nodes for workloads.
- **Cache and static files:** Redis → ElastiCache; static files → S3 + CloudFront.
- **Terraform:** modules, remote state (S3 + DynamoDB lock), separate dev/staging/prod environments.
- **Jenkins:** controller + dynamic agents setup.

