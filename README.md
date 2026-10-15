# CI/CD Pipeline & Infrastructure Documentation

This repository contains the complete **Infrastructure as Code (IaC)** and **Continuous Integration / Continuous Delivery (CI/CD)** pipeline configuration for the **Streetcode** application. It automates server provisioning, Jenkins CI/CD setup, application containerization, testing, and deployment.

---

## Architecture & Deployment Flow

```
[ Git Commit / Push ]
          │
          ▼
   [ Jenkins Job ]
          │
  ┌───────┴──────────────────────────────────────────────────┐
  │ 1. Checkout SCM (Fetches targeted git branch)            │
  │ 2. Run Tests (Parallel Stage)                            │
  │    ├── Backend Unit Tests (.NET 6.0 Container)           │
  │    └── Frontend Unit Tests (Node.js 18 Container)        │
  │ 3. Deploy via Ansible                                    │
  │    └── Executes site.yml on Target Host (streetcode_vm)  │
  │ 4. Smoke Test                                            │
  │    └── HTTP Healthcheck (curl port 3000)                 │
  │ 5. Post Actions                                          │
  │    └── Workspace Cleanup & Pipeline Status Report        │
  └──────────────────────────────────────────────────────────┘
```

---

## Repository File Structure & Descriptions

```text
.
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
└── site.yml                     # Main Ansible playbook orchestrating all deployment roles
```

---

## Pipeline Execution Stages

1. **Checkout SCM**:
   - Jenkins connects to GitHub (`streetcode-devops.git`) and checks out the targeted revision (e.g., `jenkins` or `main`).
2. **Run Tests (Parallel)**:
   - **Backend**: Launches `mcr.microsoft.com/dotnet/sdk:6.0` container, mounts workspace, and executes `dotnet test`.
   - **Frontend**: Launches `node:18` container, mounts workspace, and executes `npm run test` (with `--passWithNoTests`).
3. **Deploy via Ansible**:
   - Retrieves SSH key from Jenkins credentials store (`sshUserPrivateKey`).
   - Runs `ansible-playbook -i inventory/jenkins.yml site.yml --tags app -e target_user=${TARGET_USER}`.
   - Ansible updates application source code on the VM, creates `.env`, and rebuilds containers.
4. **Smoke Test**:
   - Sends an HTTP request via `curl` to `http://localhost:3000/` (or `http://host.docker.internal:3000/`) to verify application availability.
   - *Note:* This works because Jenkins runs on the same target host (`streetcode_vm`) using host networking (`network_mode: host`) or Docker socket sharing, allowing the Jenkins container to access ports exposed on the VM's loopback interface.
5. **Post Actions**:
   - Resets workspace file permissions (`chown -R 0:0`) and logs final build status (`Finished: SUCCESS`).

---

## Setup & Usage Guide

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
   jenkins_admin_password: "YourSecurePasswordHere"
   db_password: "YourDatabasePassword"
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
ansible-playbook -i inventory/jenkins.yml site.yml --tags app -e target_user=<YOUR_USERNAME>
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