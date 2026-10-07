# Ansible Deployment — Streetcode DevOps

This branch contains the Ansible playbooks and roles designed to **automatically provision the target server** (install Docker, configure permissions) and **deploy the Streetcode web application** (Frontend, Backend, MS SQL Database) via Docker Compose.

---

## 🏗 Architecture & Ansible Roles

The deployment process is organized into structured Ansible roles:

| Role | Description | Main Tasks |
| :--- | :--- | :--- |
| **`common`** | System pre-configuration | Ensures passwordless `sudo` (`/etc/sudoers.d/ansible_nopasswd`), updates APT cache, installs base dependencies. |
| **`docker`** | Docker environment setup | Adds official Docker GPG key, configures repository, installs `docker-ce` and `docker-compose-plugin`. |
| **`streetcode_app`** | Application deployment | Clones repository, generates `.env`, builds Docker images, runs containers, and verifies service health. |

---

## ⚙️ Prerequisites & SSH Setup

Before running the playbook, ensure your environment satisfies the following requirements:

- **Operating System:** Linux / Ubuntu (tested on Ubuntu 22.04 LTS)
- **Ansible:** Installed on the Control Node (`sudo apt install ansible` or `pip install ansible`)
- **Git:** Installed on both Control Node and Target Server
- **Target User:** A user with `sudo` privileges on the target machine
- **Free Ports:** Ensure ports `1433`, `5000`, and `3000` are not in use
### 🔑 SSH Configuration (For Remote Management)

If you are running Ansible from a local machine/CI-CD agent to manage a remote server:

1. **Generate SSH key pair** (if not already present):

```bash
   ssh-keygen -t ed25519 -C "ansible-deploy"
```

2. **Copy the public key to the target server:**

```bash
   ssh-copy-id <your_username>@<target_server_ip>
```

3. **Verify SSH access** (passwordless SSH login):

```bash
   ssh <your_username>@<target_server_ip>
```

---

## 🚀 Step-by-Step Installation & Deployment Guide

### Step 1: Clone the Repository

Clone the project repository and switch to the `ansible` branch (or your working branch):

```bash
git clone https://github.com/yaremyndaryna/streetcode-devops.git streetcode-devops
cd streetcode-devops
```

### Step 2: Configure Inventory & Variables

**1. Verify the inventory file (`inventory`):**

For **local VM** deployment:

```ini
[streetcode_servers]
streetcode_vm ansible_host=127.0.0.1 ansible_connection=local
```

For **remote server** deployment:

```ini
[streetcode_servers]
streetcode_vm ansible_host=<target_server_ip> ansible_user=<your_username>
```

**2. Verify playbook variables:**

Ensure target ports, repository URLs, and credentials in `site.yml` or `group_vars/` match your environment.

### Step 3: Run the Ansible Playbook

#### First-Time Bootstrap Run (requires sudo password once)

For the very first execution on a clean VM, pass the `-K` (`--ask-become-pass`) flag so Ansible can create the passwordless sudoers configuration:

```bash
ansible-playbook site.yml -e "target_user=<your_username>" -K
```

> **Note:** Replace <your_username> with your actual system username (run whoami to check). Enter your user's sudo password when prompted with BECOME password:.

#### Subsequent Runs (fully automated / CI-CD)

Once passwordless sudo is configured, you can run automated deployments without any password prompt:

```bash
ansible-playbook site.yml -e "target_user=<your_username>"
```

### Step 4: Verify Deployment Status

The playbook automatically performs a `docker compose ps` check at the end of execution. You can also manually verify that all containers are running:

```bash
docker ps
```

Expected active containers:

- `streetcode-db` (MS SQL Server)
- `streetcode-backend` (.NET 6 Web API)
- `streetcode-frontend` (React + Nginx)

---

## 🌐 Application Access

Once the playbook completes with `failed=0`, access the application in your browser:

- **Frontend App:** `http://localhost:3000` or `http://<YOUR_VM_IP>:3000`
- **Backend API (Swagger):** `http://localhost:5000/swagger/index.html` or `http://<YOUR_VM_IP>:5000/swagger/index.html`

---

## 🧹 Maintenance & Useful Commands

**Re-run deployment with verbose output (for debugging):**

```bash
ansible-playbook site.yml -e "target_user=<your_username>" -vvv
```

**Check logs of the deployed application containers:**

```bash
docker compose logs -f
```

**Tear down application containers via Docker Compose:**

```bash
docker compose down
```