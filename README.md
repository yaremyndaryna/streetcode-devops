# CI/CD Pipeline & Infrastructure Documentation

This repository contains the complete **Infrastructure as Code (IaC)** and **Continuous Integration / Continuous Delivery (CI/CD)** pipeline configuration for the **Streetcode** application. It automates server provisioning, Jenkins CI/CD setup, Continuous Code & Security Inspection (SonarCloud, Snyk, Trivy), application containerization, load balancing, artifact registry publishing, health/monitoring checks, and automated deployment.


---

## Architecture & Deployment Flow

```text
[ Git Commit / Push ]
          │
          ▼
   [ GitHub Actions ] ──► (SonarCloud Code Analysis + Snyk Vulnerability Scan + Trivy Container Security)
          │
          ▼
    [ Jenkins Job ]
          │
  ┌───────┴────────────────────────────────────────────────────────────────┐
  │ 1. Checkout SCM (Fetches targeted git branch)                          │
  │ 2. Check GitHub Security & Quality Status                              │
  │    └── Verifies commit check-runs via GitHub API (Sonar, Snyk, Trivy)  │
  │ 3. Run Tests (Parallel Stage)                                          │
  │    ├── Backend Unit Tests (.NET 6.0 Container)                         │
  │    └── Frontend Unit Tests (Node.js 18 Container)                      │
  │ 4. Deploy via Ansible                                                  │
  │    └── Executes site.yml on Target Host (streetcode_vm)                │
  │        ├── Spawns streetcode-db (MS SQL) & redis                       │
  │        ├── Builds & launches streetcode-backend                        │
  │        ├── Launches streetcode-app-1 & streetcode-app-2                │
  │        ├── Configures Nginx Load Balancer (streetcode-lb)              │
  │        └── Deploys Monitoring Stack (Prometheus, Grafana, cAdvisor)    │
  │ 5. Push Artifacts to GHCR                                              │
  │    └── Tags and pushes backend & frontend images to GitHub Packages    │
  │ 6. Verify Monitoring Status                                            │
  │    └── Checks health endpoints for Prometheus & Grafana                │
  │ 7. Smoke Test                                                          │
  │    └── HTTP Healthcheck via Nginx LB (curl port 3000)                  │
  │ 8. Post Actions                                                        │
  │    └── Workspace Cleanup & Pipeline Status Report                      │
  └────────────────────────────────────────────────────────────────────────┘
```
---

## Repository File Structure & Descriptions

```text
.
├── .github/
│   └── workflows/
│       └── main.yml      # GitHub Actions workflow executing SonarCloud, Snyk CLI & Trivy container scans
├── group_vars/
│   └── all/            # Global Ansible variables shared across playbooks
│       ├── main.yml       # Non-secret variables (repos, branches, DB, users)
│       └── secrets.yml    # Secrets (git-ignored, encrypt with ansible-vault)
├── inventory/
│   ├── bootstrap.yml            # Inventory for initial VM provisioning & bootstrapping
│   └── jenkins.yml              # Inventory defining target deployment host (streetcode_vm)
├── roles/
│   ├── common/
│   │   └── tasks/               # Core system dependencies, packages, and base VM setup
│   ├── docker/
│   │   └── tasks/               # Automated Docker Engine & Docker Compose installation
│   ├── jenkins/
│   │   ├── defaults/
│   │   │   └── main.yml         # Default parameters for Jenkins container configuration
│   │   ├── files/
│   │   │   ├── Dockerfile       # Custom Jenkins image build definition
│   │   │   ├── jenkins.yaml     # Jenkins Configuration as Code (JCasC) definition
│   │   │   └── plugins.txt      # Pre-installed Jenkins plugins list
│   │   ├── tasks/
│   │   │   └── main.yml         # Tasks for provisioning Jenkins container and services
│   │   └── templates/
│   │       └── docker-compose.jenkins.yml.j2  # Jinja2 template to run Jenkins in Docker
│   └── streetcode_app/
│       └── tasks/               # Application deployment tasks (Git clone, .env, compose up)
├── .gitignore                   # Excluded files and directories from Git tracking
├── ansible.cfg                  # Ansible CLI configuration (roles path, SSH settings)
├── Jenkinsfile                  # Primary Declarative Pipeline script for Jenkins CI/CD
├── LICENSE                      # Project open-source license
├── README.md                    # Project documentation
├── requirements.yml             # External Ansible roles/collections dependencies
├── site.yml                     # Main Ansible playbook orchestrating all deployment roles
└── sonar-project.properties     # SonarCloud analysis configuration (project key, organization, sources, and exclusions)
```
> **Note:** Application stack assets (`docker-compose.yml`, `lb/nginx.conf`, and application source code) are maintained in the targeted application branch `load-balancer`, which is cloned by Ansible during deployment.

---
## Pipeline Execution Stages

1. **Checkout SCM**:
* Jenkins connects to GitHub (`streetcode-devops.git`) and checks out the targeted revision (e.g., `jenkins` or `main`).


2. **Check GitHub Security & Quality Status**:
* Connects to GitHub Check Runs API (`api.github.com/repos/yaremyndaryna/streetcode-devops/commits/${env.GIT_COMMIT}/check-runs`).
* Verifies that the GitHub Actions job `Build, Analyze & Security Scan` (SonarCloud analysis, Snyk, Trivy) has completed successfully for the commit.
* **Important:** this stage confirms that the analysis pipeline *ran without technical errors*. It does **not** enforce code quality or security results:

  | Check | Configuration | Fails the job on findings? |
  |-------|---------------|----------------------------|
  | SonarCloud | Analysis is uploaded; Quality Gate result is not awaited | ❌ No |
  | Snyk | `continue-on-error: true` | ❌ No |
  | Trivy | `exit-code: '0'` | ❌ No |

  Results must be reviewed manually in SonarCloud and in the GitHub Actions logs.

3. **Run Tests (Parallel)**:
* **Backend**: Launches `mcr.microsoft.com/dotnet/sdk:6.0` container, mounts workspace, and executes `dotnet test`.
* **Frontend**: Launches `node:18` container, mounts workspace, and executes `npm run test` (with `--passWithNoTests`).


4. **Deploy via Ansible & Setup Load Balancing**:
* Retrieves SSH key from Jenkins credentials store (`sshUserPrivateKey`).
* Runs `ansible-playbook -i inventory/jenkins.yml site.yml --tags app -e target_user=${TARGET_USER}`.
* Ansible clones/pulls the application stack, builds backend/frontend images, and spins up:
* `streetcode-db` (MS SQL Server 2022 with healthcheck)
* `streetcode-redis` (Redis 7 Cache)
* `streetcode-backend` (.NET 6 Web API)
* `streetcode-app-1` & `streetcode-app-2` (Replicated Frontend Nodes)
* `streetcode-lb` (Nginx Reverse Proxy & Load Balancer listening on port 3000)
*  Monitoring Stack: `streetcode-prometheus` (Port 9090), `streetcode-grafana` (Port 3001), `streetcode-node-exporter`, and `streetcode-cadvisor`.


5. **Push Artifacts to GHCR**:
* Logs into **GitHub Container Registry** (ghcr.io).
* Tags locally built images with build number (${env.BUILD_NUMBER}) and :latest.
* Pushes both streetcode-backend and streetcode-frontend images to GHCR for artifact retention and release tracking.


6. **Verify Monitoring Status**:
* Performs automated health checks on the deployed monitoring services via internal host routing (host.docker.internal):
* **Prometheus**: http://host.docker.internal:9090/-/healthy
* **Grafana**: http://host.docker.internal:3001/api/health

7. **Smoke Test**:
* Sends an HTTP request via `curl` to `http://host.docker.internal:3000/` (or `http://localhost:3000/`) to verify frontend accessibility through the Nginx Load Balancer.

8. **Post Actions**:
* Resets workspace file permissions (`chown -R 0:0`) and logs final build status (`Finished: SUCCESS`).

---
## Setup & Usage Guide
### Before You Start: Adapt the Configuration to Your Environment

The repository contains values that belong to the original project. If you fork or reuse it, replace them with your own **before the first run**.

#### 1. Ansible variables (`group_vars/all/main.yml`)

This file holds **non-secret** settings and is tracked in Git (secrets live separately in `secrets.yml`). Review every value:

```yaml
app_repo: "https://github.com/<YOUR_GITHUB_USER>/<YOUR_REPO>.git"   # repository with the application stack
app_branch: "load-balancer"                                         # branch with docker-compose.yml, lb/nginx.conf, sources
app_dir: "/home/{{ target_user }}/streetcode-app"                   # deployment directory on the target host
db_port: 1433
db_user: "sa"
db_name: "StreetcodeDb"
target_user: "ubuntu"                                               # Linux user on the target VM
jenkins_repo_url: "https://github.com/<YOUR_GITHUB_USER>/<YOUR_REPO>.git"  # repository Jenkins pulls the Jenkinsfile from
jenkins_repo_branch: "jenkins"                                      # branch Jenkins builds
github_user: "<YOUR_GITHUB_USER>"                                   # used for GHCR login and image names
```

> **Important:** never put passwords or tokens in this file. Use `group_vars/all/secrets.yml` for `db_password`, `github_token`, etc.

#### 2. GitHub Actions workflow (`.github/workflows/main.yml`)

Open the file and replace the values that belong to the original repository:

| Setting | Where in `main.yml` | What to set |
|---------|--------------------|-------------|
| SonarCloud project key | `dotnet-sonarscanner begin`, `/k:"streetcode-devops"` | Your SonarCloud project key |
| SonarCloud organization | `dotnet-sonarscanner begin`, `/o:"yaremyndaryna"` | Your SonarCloud organization |
| Trigger branches | `on.push.branches` | Branches that exist in your repository |
| Backend / frontend / Snyk paths | `dotnet build ...`, `cd apps/frontend`, `--file=...` | Paths matching your project layout |
| Dockerfile source branch and paths | `ref: load-balancer`, `load-balancer-src/apps/.../Dockerfile` | Your branch and Dockerfile locations |

#### 3. Other places to check

1. **`Jenkinsfile`:** the Check Runs API URL (`api.github.com/repos/<owner>/<repo>/commits/...`) and the default `TARGET_USER` must match your repository and user.
2. **`sonar-project.properties`:** `sonar.projectKey` and `sonar.organization` must match the values in `main.yml`.
3. **GitHub repository secrets:** `SONAR_TOKEN` and `SNYK_TOKEN` must exist (**Settings > Secrets and variables > Actions**).
4. **Test run:** push a commit and confirm in the **Actions** tab that the job `Build, Analyze & Security Scan` finishes successfully before running the Jenkins pipeline.

### Continuous Code Inspection Setup (SonarCloud & GitHub Actions)

To enable automated code analysis and pass the **Check GitHub Security & Quality Status** stage in Jenkins:

1. **Create a SonarCloud Account & Project**:
   - Register on [SonarCloud.io](https://sonarcloud.io/) and import your GitHub repository.
2. **Update `sonar-project.properties`**:
   - Set your own project key and organization in `main.yml` (`/k:` and `/o:`) and keep `sonar-project.properties` consistent with them (see *Before You Start*).
3. **Configure GitHub Repository Secret**:
   - Generate an Access Token in SonarCloud (**Account > Security > Generate Tokens**).
   - In your GitHub Repository, go to **Settings > Secrets and variables > Actions > New repository secret**.
   - Add a secret named `SONAR_TOKEN` with your SonarCloud token value.
4. **GitHub Action Automation**:
   - GitHub Actions scans commits on push/PR and uploads the analysis to SonarCloud. The Quality Gate result is visible in SonarCloud; the workflow does not enforce it (see *Security & Quality Scanners Behavior*).


### Snyk Setup (Vulnerability Scanning)

1. **Create a Snyk Account**:
   - Register on [Snyk.io](https://snyk.io/) and connect your GitHub account.
2. **Configure GitHub Repository Secret**:
   - Generate an API Token in Snyk (**Account Settings > API Token**).
   - In your GitHub Repository, go to **Settings > Secrets and variables > Actions > New repository secret**.
   - Add a secret named `SNYK_TOKEN` with your Snyk API token value.
3. **GitHub Action Automation**:
   - Ensure Snyk scanning steps are configured in `.github/workflows/main.yml`. GitHub Actions will automatically scan backend NuGet packages and frontend npm dependencies for vulnerabilities on every push/PR.
   - Findings (severity `high` and above) are printed in the workflow job log. The Snyk steps run with `continue-on-error: true`, so vulnerabilities do **not** fail the job (see *Security & Quality Scanners Behavior*).


### GitHub Personal Access Token (PAT) Setup for Jenkins & GHCR
To enable Jenkins to publish Docker images to GitHub Container Registry (GHCR) and interact with the GitHub Check Runs API, configure the github-credentials entry via Jenkins Configuration as Code (JCasC):

1. **Generate Personal Access Token (PAT) in GitHub**:
   - Navigate to GitHub Settings > Developer Settings > Personal access tokens > Tokens (classic).
   - Click Generate new token (classic).
   - Set the Note (e.g., Jenkins CI/CD GHCR Token).
   - Select the required scopes:
      * **repo** (Full control of private repositories & status checks)
      * **write:packages** (To upload Docker images to GitHub Container Registry)
      * **read:packages** (To download Docker images from GHCR)
      * **workflow** (To read/manage GitHub Actions workflows)

2. **Add Token to Secrets Configuration**:
   - Copy the generated token string (it will only be displayed once).
   - Open your local `group_vars/all/secrets.yml` file and add the token under the variable name `github_token`

---


### Prerequisites

* **Target Host**: Ubuntu Virtual Machine with SSH access and sudo privileges.
* **Jenkins Server**: Running inside Docker via the `jenkins` role.

### Configuration & Deployment Setup

#### 1. Secrets Configuration (`group_vars/all/secrets.yml`)

Before executing any playbooks, create a dedicated file to store confidential variables (passwords, tokens, API keys):

1. **Exclude the file from Git first:**

   ```bash
   echo "group_vars/all/secrets.yml" >> .gitignore
   ```

2. **Create the secrets file:**

   ```yaml
   # group_vars/all/secrets.yml
   jenkins_admin_password: "CHANGE_ME"
   db_password: "CHANGE_ME"
   github_token: "CHANGE_ME"
   redis_password: "CHANGE_ME"
   gf_security_admin_password: "CHANGE_ME"
   ```


*Verification:* `git status` must not list `secrets.yml`.

---

#### 2. Provisioning and Deployment Commands

##### Install Dependencies

Install external Ansible roles and collections:

```bash
ansible-galaxy install -r requirements.yml
```

##### Initial Provisioning (First-time setup)

To provision a clean server with base dependencies, Docker, and Jenkins:

```bash
ansible-playbook -i inventory/bootstrap.yml site.yml
```

##### Application Deployment Only

To deploy or update only the application stack:

```bash
ansible-playbook -i inventory/jenkins.yml site.yml -e target_user=<YOUR_USERNAME>
```

---

#### 3. Accessing Jenkins

1. **Open your browser:**

   Navigate to your server's IP address on port `8080`:

   ```
   http://<YOUR_SERVER_IP>:8080
   ```

2. **Sign In:**
   * **Username:** `admin` (or the custom admin user defined in your playbooks)
   * **Password:** Use the password set in `group_vars/all/secrets.yml` (`jenkins_admin_password`)

> **Note:** Because the administrator password is automatically pre-configured during deployment via Ansible variables, the default `initialAdminPassword` setup flow is bypassed.

---

#### 4. Running the Jenkins Pipeline

The pipeline supports both automatic triggers and manual parameter overrides:

* **Automatic Builds (`git push`):**
  When a commit is pushed to the repository, Jenkins automatically triggers the pipeline using the default parameter value (`defaultValue`) defined in the `Jenkinsfile`.

* **Manual Builds (Custom Target User):**
  If you need to deploy the application for a different user, trigger the build manually:
  1. Open the job dashboard in Jenkins and click **Build with Parameters**.
  2. Enter the desired username in the `TARGET_USER` field.
  3. Click **Build**.

> **Note:** To change the fallback user for automatic builds, update the `defaultValue` attribute in your `Jenkinsfile`:
>
> ```groovy
> parameters {
>     string(name: 'TARGET_USER', defaultValue: 'your_username', description: 'Deployment target Linux user')
> }
> ```

## Accessing Services
* Jenkins Dashboard: http://<YOUR_SERVER_IP>:8080
   * **Username:** `admin` (or the custom admin user defined in your playbooks)
   * **Password:** Use the password set in `group_vars/all/secrets.yml` (`jenkins_admin_password`)

* Application (via Nginx LB): http://<YOUR_SERVER_IP>:3000

* Prometheus: http://<YOUR_SERVER_IP>:9090

* Grafana Dashboard: http://<YOUR_SERVER_IP>:3001
   * **Username:** `admin` (or the custom admin user defined in your playbooks) 
   * **Password:** Use the password set in `group_vars/all/secrets.yml` (`gf_security_admin_password`)


### Security & Quality Scanners Behavior (SonarCloud, Snyk & Trivy)

> All three tools currently run in **audit/monitoring mode** and do **not** act as deployment gates. The Jenkins stage "Check GitHub Security & Quality Status" fails only if the GitHub Actions job itself fails for technical reasons (checkout, build, invalid tokens, etc.).
>
> - **SonarCloud:** analysis results are uploaded, but the workflow does not wait for or enforce the Quality Gate.
> - **Snyk:** `continue-on-error: true`; vulnerabilities (severity ≥ high) are logged without failing the workflow.
> - **Trivy:** `exit-code: '0'` and `ignore-unfixed: true`; `HIGH`/`CRITICAL` findings are printed to the log only.
>
> **To turn them into blocking gates:**
> - SonarCloud: add `/d:sonar.qualitygate.wait=true` to `dotnet-sonarscanner begin`.
> - Snyk: remove `continue-on-error: true`.
> - Trivy: set `exit-code: '1'`.