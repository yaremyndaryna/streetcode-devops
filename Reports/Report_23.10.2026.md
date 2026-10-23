**Period:** 16.10.2026 – 23.10.2026

**Report date:** 23.10.2026

---

# Progress Report: Continuous Code Inspection (SonarCloud), Nginx Load Balancing & Redis Session Management Setup

|  |  |
| --- | --- |
| **Module** | Continuous Code Inspection (CCI), High Availability & Infrastructure as Code |
| **Project** | Streetcode Web Application (`streetcode-devops`) |
| **Author** | Daryna Yaremyn |
| **Status** | ✅ Completed (final pipeline run: `SUCCESS`) |
| **Technologies** | Jenkins (Declarative Pipeline), Ansible, Docker, Docker Compose, Nginx, Redis 7, SonarCloud, GitHub Actions, MS SQL Server 2022, .NET 6, Node.js 18, Git, Ubuntu 22.04 LTS |
| **Repository** | [https://github.com/yaremyndaryna/streetcode-devops](https://github.com/yaremyndaryna/streetcode-devops) |

---

## Module Objective

The main goal of this iteration was to enhance the existing CI/CD and deployment architecture for the Streetcode web application by:

1. Integrating **Continuous Code Inspection (CCI)** via **SonarCloud** and GitHub Actions into the Jenkins pipeline.
2. Transitioning the frontend architecture to a high-availability reverse-proxy model using an **Nginx Load Balancer** with **Round-Robin** traffic distribution.
3. Setting up **Redis 7** for centralized distributed session management, ensuring failover resilience across replicated application containers (`streetcode-app-1` and `streetcode-app-2`).

---

## Implemented Architecture & Infrastructure Overview

Before this setup, the frontend container was directly exposed to the host system. The application stack has been transitioned into an isolated internal Docker network fronted by Nginx, backed by persistent database storage and distributed Redis caching:

```text
                                  +-----------------------------------+
                                  |        Client / Browser           |
                                  +-----------------------------------+
                                                    |
                                                    | Port 3000
                                                    v
                                  +-----------------------------------+
                                  |    streetcode-lb (Nginx Proxy)    |
                                  +-----------------------------------+
                                               /         \
                                (Round-Robin) /           \ (Round-Robin)
                                             v             v
                       +-------------------------+     +-------------------------+
                       |  streetcode-app-1       |     |  streetcode-app-2       |
                       |  (Frontend Replica 1)   |     |  (Frontend Replica 2)   |
                       +-------------------------+     +-------------------------+
                                               \         /
                                                v       v
                                    +----------------------------------+
                                    | streetcode-backend (.NET Core)   |
                                    +----------------------------------+
                                                    |
                                                    |
                                                    +-----------------------------------+
                                                    |                                   |
                                                    v                                   v
                                    +----------------------------------+ +----------------------------------+
                                    |  streetcode-db (MS SQL Server)   | |   streetcode-redis (Redis 7)    |
                                    +----------------------------------+ +----------------------------------+

```

---

## Implemented CI/CD Pipeline Flow

```text
[ Git Commit / Push ]
          │
          ▼
   [ Jenkins Job ]
          │
  ┌───────┴──────────────────────────────────────────────────┐
  │ 1. Checkout SCM (Fetches targeted Git branch)            │
  │ 2. Check SonarCloud Status (Continuous Code Inspection)  │
  │    └── Verifies commit check-runs via GitHub API         │
  │ 3. Run Tests (Parallel Stage)                            │
  │    ├── Backend Unit Tests (.NET 6.0 Container)           │
  │    └── Frontend Unit Tests (Node.js 18 Container)        │
  │ 4. Deploy via Ansible & Setup Load Balancing             │
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

## 📋 Tasks Completed

### 1. Continuous Code Inspection (SonarCloud & GitHub Actions)

* Configured project-level static code analysis in `sonar-project.properties` specifying project metadata (`sonar.projectKey`, `sonar.organization`), source directories, and exclusions.
* Integrated automated code analysis via GitHub Actions (`.github/workflows/sonar.yml`).
* Implemented a dedicated pipeline stage in `Jenkinsfile` (`Check SonarCloud Status`) querying the GitHub Check Runs API (`https://api.github.com/repos/yaremyndaryna/streetcode-devops/commits/${env.GIT_COMMIT}/check-runs`) to enforce Quality Gate verification before running tests and deployment.

### 2. High Availability Nginx Load Balancing & Frontend Replication

* Isolated frontend containers (`streetcode-app-1`, `streetcode-app-2`) from direct host port exposure, restricting traffic to the internal Docker network.
* Configured **Nginx (`streetcode-lb`)** as the single public entry point on port `3000`, implementing **Round-Robin** request balancing across application replicas.
* Tested alternative load balancing algorithms in `lb/nginx.conf` including **Weighted Round-Robin** (`weight=3`) and **IP Hash (`ip_hash`)** for sticky sessions.
* Verified automatic failover capabilities by stopping `streetcode-app-1` and confirming zero-downtime request handling via `streetcode-app-2`.

### 3. Centralized Distributed Caching (Redis 7)

* Integrated a secured **Redis 7** service (`streetcode-redis`) with persistent volume storage (`dump.rdb`) for centralized session state management across backend operations.
* Enforced security best practices by handling Redis authentication via the `REDISCLI_AUTH` environment variable (preventing plain-text password exposure in system process logs).

### 4. Deployment Automation & Smoke Testing

* Updated Ansible application deployment tasks (`roles/streetcode_app/tasks/main.yml`) to clone/pull the target branch, generate `.env` configurations, and orchestrate the multi-container stack.
* Configured service health dependencies (`depends_on` with `service_healthy` conditions for database and Redis services).
* Updated the HTTP Smoke Test stage to validate application accessibility through the Nginx Load Balancer endpoint (`http://host.docker.internal:3000/`).

---

## Issues Resolved During Implementation

### 1. MS SQL Server Database Authentication Failure (`Login failed for user 'sa'`)

* **Issue:** During deployment, `streetcode-db` failed health checks, causing dependent backend services to abort startup with `container streetcode-db is unhealthy`. Log analysis showed `Login failed for user 'sa' (Error 18456, State 8)` caused by literal variable non-expansion (`'${SA_PASSWORD}'`) inside single quotes in the `healthcheck` string, as well as stale credentials stored in existing Docker volumes.
* **Solution:** Formatted the `healthcheck` command in `docker-compose.yml` to ensure double-quoted variable interpolation (`"$SA_PASSWORD"`), purged stale database volumes via `docker volume prune`, and aligned credential variables across environment files and deployment scripts.

### 2. Stale Jenkins Pipeline Job Configuration & Unprocessed Jinja2 Templates
* **Issue:** The Jenkins build executed outdated pipeline definitions because cached job configurations persisted inside `/var/jenkins_home/jobs/streetcode-pipeline`, preventing updated JCasC variables (`{{ ... }}`) from applying.
* **Solution:** Applied the Ansible playbook with explicit Jenkins tags to re-render the JCasC template (`ansible-playbook -i inventory/jenkins.yml site.yml -b --tags jenkins -e target_user=<USERNAME>`), manually removed the stale job configuration directory (`docker exec -it jenkins-ci rm -rf /var/jenkins_home/jobs/streetcode-pipeline`), and restarted the Jenkins container (`docker restart jenkins-ci`) to force clean job initialization.

---

## Verification & Results

All pipeline stages and local verification steps completed successfully.

### 1. Local Container & Redis Connectivity Check

```bash
$ docker exec -it -e REDISCLI_AUTH="$(grep REDIS_PASSWORD .env | cut -d '=' -f2)" streetcode-redis redis-cli ping
PONG

```

### 2. Jenkins Console Log Excerpt (Final Pipeline Run)

```text
14:08:24  ✅ SonarCloud status verified successfully. Proceeding with tests and deployment...
...
14:12:26  ok: [streetcode_vm] => {
14:12:26      "compose_ps_output.stdout_lines": [
14:12:26          "NAME                 IMAGE                                        COMMAND                  SERVICE            CREATED              STATUS                        PORTS",
14:12:26          "streetcode-app-1     streetcode-app-streetcode-app-1              \"/docker-entrypoint.…\"   streetcode-app-1   About a minute ago   Up 7 seconds                  80/tcp",
14:12:26          "streetcode-app-2     streetcode-app-streetcode-app-2              \"/docker-entrypoint.…\"   streetcode-app-2   About a minute ago   Up 7 seconds                  80/tcp",
14:12:26          "streetcode-backend   streetcode-app-backend                       \"dotnet Streetcode.W…\"   backend            About a minute ago   Up 8 seconds                  0.0.0.0:5000->5000/tcp, [::]:5000->5000/tcp",
14:12:26          "streetcode-db        mcr.microsoft.com/mssql/server:2022-latest   \"/opt/mssql/bin/laun…\"   streetcode-db      About a minute ago   Up About a minute (healthy)   0.0.0.0:1433->1433/tcp, [::]:1433->1433/tcp",
14:12:26          "streetcode-lb        nginx:alpine                                 \"/docker-entrypoint.…\"   nginx-lb           About a minute ago   Up 5 seconds                  0.0.0.0:3000->80/tcp, [::]:3000->80/tcp",
14:12:26          "streetcode-redis     redis:7-alpine                               \"docker-entrypoint.s…\"   redis              About a minute ago   Up About a minute (healthy)   0.0.0.0:6379->6379/tcp, [::]:6379->6379/tcp"
14:12:26      ]
14:12:26  }
...
14:12:28  + curl -fsS --retry 10 --retry-delay 3 http://host.docker.internal:3000/
14:12:28  ✅ Frontend is accessible on port 3000!
...
14:12:30  ✅ Pipeline finished successfully: Tests passed and application deployed!

Finished: SUCCESS

```

---

## Conclusions

* **Continuous Code Inspection (CCI)** is fully integrated into the CI/CD pipeline, automatically enforcing SonarCloud Quality Gate compliance on every commit.
* **High Availability & Failover** have been achieved for the web application frontend using Nginx reverse proxying and container replication.
* **Centralized Session Management** via Redis ensures state persistence across scaled backend replicas.
* The pipeline fully automates build, static code quality checking, testing, deployment, and health verification in a single automated process.