# CI/CD Pipeline & Infrastructure Documentation

This repository contains the complete **Infrastructure as Code (IaC)** and **Continuous Integration / Continuous Delivery (CI/CD)** pipeline configuration for the **Streetcode** application. It automates server provisioning, Jenkins CI/CD setup, Continuous Code Inspection (SonarCloud), application containerization, load balancing, unit testing, and deployment.


---

## Architecture & Deployment Flow

```text
[ Git Commit / Push ]
          │
          ▼
   [ Jenkins Job ]
          │
  ┌───────┴──────────────────────────────────────────────────┐
  │ 1. Checkout SCM (Fetches targeted git branch)            │
  │ 2. Check SonarCloud Status (Continuous Code Inspection)  │
  │    └── Verifies commit check-runs via GitHub API         │
  │ 3. Run Tests (Parallel Stage)                            │
  │    ├── Backend Unit Tests (.NET 6.0 Container)           │
  │    └── Frontend Unit Tests (Node.js 18 Container)        │
  │ 4. Deploy via Ansible                                    │
  │    └── Executes site.yml on Target Host (streetcode_vm)  │
  │        ├── Spawns streetcode-db (MS SQL) & redis         │
  │        ├── Builds streetcode-backend                     │
  │        ├── Launches streetcode-app-1 & streetcode-app-2  │
  │        └── Configures Nginx Load Balancer (streetcode-lb)│
  │ 5. Smoke Test                                            │
  │    └── HTTP Healthcheck via Nginx LB (curl port 3000)    │
  │ 6. Post Actions                                          │
  │    └── Workspace Cleanup & Pipeline Status Report        │
  └──────────────────────────────────────────────────────────┘
```
---

## Repository File Structure & Descriptions

```text
.
├── .github/
│   └── workflows/
│       └── sonar.yml      # GitHub Actions workflow executing SonarCloud scan on push/PR
├── group_vars/
│   └── all/                     # Global Ansible variables shared across playbooks
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


2. **Check SonarCloud Status (Continuous Code Inspection - CCI)**:
* Connects to GitHub Check Runs API (`api.github.com/repos/yaremyndaryna/streetcode-devops/commits/${env.GIT_COMMIT}/check-runs`).
* Verifies that SonarCloud static code analysis and quality gate checks have passed for the current commit before allowing deployment.


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

5. **Smoke Test**:
* Sends an HTTP request via `curl` to `http://host.docker.internal:3000/` (or `http://localhost:3000/`) to verify frontend accessibility through the Nginx Load Balancer.

6. **Post Actions**:
* Resets workspace file permissions (`chown -R 0:0`) and logs final build status (`Finished: SUCCESS`).

---
## Setup & Usage Guide

### Continuous Code Inspection Setup (SonarCloud & GitHub Actions)

To enable automated code analysis and pass the **Check SonarCloud Status** stage in Jenkins:

1. **Create a SonarCloud Account & Project**:
   - Register on [SonarCloud.io](https://sonarcloud.io/) and import your GitHub repository.
2. **Update `sonar-project.properties`**:
   - Set your own `sonar.projectKey` and `sonar.organization` values in `sonar-project.properties`.
3. **Configure GitHub Repository Secret**:
   - Generate an Access Token in SonarCloud (**Account > Security > Generate Tokens**).
   - In your GitHub Repository, go to **Settings > Secrets and variables > Actions > New repository secret**.
   - Add a secret named `SONAR_TOKEN` with your SonarCloud token value.
4. **GitHub Action Automation**:
   - Ensure `.github/workflows/sonar.yml` is present in your repository. GitHub Actions will automatically scan your commits on push and report Quality Gate status directly to GitHub Check Runs API.


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
   sa_password: "CHANGE_ME"
   ```

3. **Encrypt it (recommended):**

   ```bash
   ansible-vault encrypt group_vars/all/secrets.yml
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