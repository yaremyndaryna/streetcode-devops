**Period:** 24.10.2026 – 28.10.2026

**Report date:** 28.10.2026

---

# Progress Report: Advanced Security Scanning Pipeline (Snyk, Trivy), Infrastructure Monitoring & GHCR Publishing

|  |  |
| --- | --- |
| **Module** | Security Scanning Automation, GHCR Artifact Management & Infrastructure Monitoring |
| **Project** | Streetcode Web Application (`streetcode-devops`) |
| **Author** | Daryna Yaremyn |
| **Status** | ✅ Completed (final pipeline run `#39`: `SUCCESS`) |
| **Technologies** | Jenkins (Declarative Pipeline & JCasC), Ansible, Docker, Docker Compose, GitHub Actions, SonarCloud, Snyk CLI, Trivy, GHCR (GitHub Container Registry), Prometheus v2.45, Grafana 10.0, Node Exporter, cAdvisor, Nginx, Redis 7, MS SQL Server 2022, .NET 6, Node.js 18, Git, Ubuntu 22.04 LTS |
| **Repository** | [https://github.com/yaremyndaryna/streetcode-devops](https://github.com/yaremyndaryna/streetcode-devops) |

---

## Module Objective

The main goal of this iteration was to complete the full automation of the CI/CD pipeline and infrastructure stack by:

1. Expanding **GitHub Actions security workflows** to include **Snyk** (dependency vulnerability scanning) and **Trivy** (Docker image vulnerability scanning) alongside **SonarCloud** static code analysis.
2. Integrating **GitHub Container Registry (GHCR)** image tagging and publishing directly within the Jenkins deployment lifecycle.
3. Deploying a comprehensive **Monitoring and Observability Stack** comprising **Prometheus**, **Grafana**, **Node Exporter**, and **cAdvisor**.
4. Adding an automated **Monitoring Health Check** stage to the Jenkins pipeline (`Verify Monitoring Status`) using host-level routing.

---

## Implemented Architecture & Infrastructure Overview

The application architecture now incorporates a dedicated telemetry and metrics collection layer alongside the high-availability reverse-proxy and database stack:

```text
                                  +-----------------------------------+
                                  |         Client / Browser          |
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
       +-------------------------+                               +-------------------------+
       |   streetcode-app-1      |                               |   streetcode-app-2      |
       |  (Frontend Replica 1)   |                               |  (Frontend Replica 2)   |
       +-------------------------+                               +-------------------------+
                               \                               /
                                v                             v
                                +-----------------------------+
                                | streetcode-backend (.NET 6) |
                                +-----------------------------+
                                               |
                     +-------------------------+-------------------------+
                     |                                                   |
                     v                                                   v
      +----------------------------+                       +----------------------------+
      | streetcode-db (MS SQL)     |                       | streetcode-redis (Redis 7) |
      +----------------------------+                       +----------------------------+

===================================================================================================
                                     MONITORING STACK
===================================================================================================

  +-------------------------------+                       +-------------------------------+
  | streetcode-node-exporter      |                       | streetcode-cadvisor           |
  | (Host CPU, RAM, Disk, Net)    |                       | (Container CPU, Memory, I/O)  |
  +-------------------------------+                       +-------------------------------+
                 | Port 9100                                              | Port 8080 (Host 8082)
                 +-----------------------+ +------------------------------+
                                         | |
                                         v v
                         +---------------------------------+
                         | streetcode-prometheus           | (Scrapes targets every 15s)
                         +---------------------------------+
                                         | Port 9090
                                         v
                         +---------------------------------+
                         | streetcode-grafana              | (Visualization Dashboards)
                         +---------------------------------+ (Port 3001)

```

---

## Implemented CI/CD Pipeline Flow

```text
[ Git Commit / Push ]
          │
          ▼
   [ GitHub Actions ] ──► (SonarCloud + Snyk Vulnerability Scan + Trivy Container Security)
          │
          ▼
    [ Jenkins Job ]
          │
  ┌───────┴────────────────────────────────────────────────────────────────┐
  │ 1. Checkout SCM (Fetches targeted Git branch)                          │
  │ 2. Check GitHub Security & Quality Status                              │
  │    └── Verifies commit check-runs via GitHub API (Sonar, Snyk, Trivy)  │
  │ 3. Run Tests (Parallel Stage)                                          │
  │    ├── Backend Unit Tests (.NET 6.0 Container)                         │
  │    └── Frontend Unit Tests (Node.js 18 Container)                      │
  │ 4. Deploy via Ansible & Setup Stack                                    │
  │    └── Executes site.yml on Target Host (streetcode_vm)                │
  │        ├── Spawns streetcode-db, redis, backend, replicas, nginx-lb    │
  │        └── Provisions Prometheus, Grafana, Node Exporter, cAdvisor     │
  │ 5. Push Artifacts to GHCR                                              │
  │    └── Tags and pushes backend/frontend images (:build_num, :latest)   │
  │ 6. Verify Monitoring Status                                            │
  │    └── Checks health endpoints for Prometheus & Grafana                │
  │ 7. Smoke Test                                                          │
  │    └── HTTP Healthcheck via Nginx LB (curl port 3000)                  │
  │ 8. Post Actions                                                        │
  │    └── Workspace Cleanup & Pipeline Status Report                      │
  └────────────────────────────────────────────────────────────────────────┘

```

---

## 📋 Tasks Completed

### 1. Multi-Layer Security Scanning Workflow (`.github/workflows/main.yml`)

* **SonarCloud Integration:** Maintained static code analysis for quality gate compliance.
* **Snyk Dependency Scanning:** Integrated Snyk CLI steps to inspect backend `.NET` dependencies (`Streetcode.sln`) and frontend `npm` packages. Configured with `continue-on-error: true` to run in audit mode, reporting security findings without halting automated CI pipeline builds for non-blocking advisories.
* **Trivy Container Scanning:** Integrated `aquasecurity/trivy-action` to build and analyze Docker images (`streetcode-backend:test` and `streetcode-frontend:test`) for OS base layer and library vulnerabilities (`HIGH,CRITICAL`). Configured with `exit-code: '0'` and `ignore-unfixed: true` for continuous security auditing.
* **Jenkins Gate Verification:** Updated the `Check GitHub Security & Quality Status` stage in `Jenkinsfile` to poll the GitHub Check Runs API and verify successful execution across all three scanners before proceeding to build and deployment.

### 2. Automated Artifact Management with GitHub Container Registry (GHCR)

* Generated a GitHub Personal Access Token (PAT) with `repo`, `write:packages`, `read:packages`, and `workflow` scopes.
* Injected PAT credentials securely via JCasC (`github-credentials`) and `group_vars/all/secrets.yml` (`github_token`).
* Implemented the `Push Artifacts to GHCR` pipeline stage to automatically authenticate (`docker login ghcr.io`), tag local build images (`streetcode-backend` and `streetcode-frontend`) with build iteration tags (`:${env.BUILD_NUMBER}`) and `:latest`, and push artifacts to GHCR.

### 3. Monitoring & Observability Stack Deployment

* Configured **Prometheus (`streetcode-prometheus`)** on port `9090` with a 15-second scraping interval (`monitoring/prometheus.yml`).
* Integrated **Node Exporter (`streetcode-node-exporter`)** on port `9100` for host-level OS performance metrics (CPU usage, RAM, disk utilization, network throughput).
* Integrated **cAdvisor (`streetcode-cadvisor`)** on port `8082` for real-time per-container memory, CPU, and network I/O stats.
* Configured **Grafana (`streetcode-grafana`)** on port `3001` with administrator authentication (`gf_security_admin_password`).

### 4. Automated Monitoring Health Verification

* Added a dedicated `Verify Monitoring Status` stage in `Jenkinsfile`.
* Automated HTTP endpoint checks for **Prometheus** (`/-/healthy`) and **Grafana** (`/api/health`) using container-to-host network routing (`host.docker.internal`).

---

## Issues Resolved During Implementation

### 1. Docker Build Context & File Location Mismatch in Trivy Scanning Step

* **Issue:** The GitHub Actions workflow failed during `docker build` for Trivy scanning with `open Dockerfile: no such file or directory`. The workflow executed from the `jenkins` branch, whereas application `Dockerfile` assets resided in the `load-balancer` branch. When using `checkout` with `path: load-balancer-src`, Docker failed to resolve relative build context paths.
* **Solution:** Updated the workflow build commands to explicitly define both the path to the Dockerfile (`-f load-balancer-src/apps/backend/Dockerfile`) and the precise root build context (`load-balancer-src/apps/backend` for backend, `load-balancer-src/apps/frontend` for frontend).

### 2. Prometheus Health Check Connection Failure (`curl: (7) Failed to connect to localhost port 9090`)

* **Issue:** During Jenkins pipeline execution, the `Verify Monitoring Status` stage failed with `curl: (7) Failed to connect to localhost port 9090`. Because Jenkins ran inside its own Docker container (`jenkins-ci`), querying `localhost` routed traffic inside the Jenkins container rather than the host VM where Prometheus was published.
* **Solution:** Replaced `localhost` with `host.docker.internal:9090` and `host.docker.internal:3001` within the `Jenkinsfile` `sh` scripts, enabling the Jenkins container to route health check requests to services running on the host network.

---

## Verification & Results

The final pipeline run (**Build #39**) completed with zero errors across all stages.

### 1. Active Container Stack Status (`docker compose ps`)

```text
NAME                       IMAGE                                        COMMAND                  SERVICE            STATUS                        PORTS
streetcode-app-1           streetcode-app-streetcode-app-1              "/docker-entrypoint.…"   streetcode-app-1   Up 7 seconds                  80/tcp
streetcode-app-2           streetcode-app-streetcode-app-2              "/docker-entrypoint.…"   streetcode-app-2   Up 7 seconds                  80/tcp
streetcode-backend         streetcode-app-backend                       "dotnet Streetcode.W…"   backend            Up 9 seconds                  0.0.0.0:5000->5000/tcp, [::]:5000->5000/tcp
streetcode-cadvisor        gcr.io/cadvisor/cadvisor:v0.47.0             "/usr/bin/cadvisor -…"   cadvisor           Up About a minute (healthy)   0.0.0.0:8082->8080/tcp, [::]:8082->8080/tcp
streetcode-db              mcr.microsoft.com/mssql/server:2022-latest   "/opt/mssql/bin/laun…"   streetcode-db      Up About a minute (healthy)   0.0.0.0:1433->1433/tcp, [::]:1433->1433/tcp
streetcode-grafana         grafana/grafana:10.0.0                       "/run.sh"                grafana            Up About a minute             0.0.0.0:3001->3000/tcp, [::]:3001->3000/tcp
streetcode-lb              nginx:alpine                                 "/docker-entrypoint.…"   nginx-lb           Up 5 seconds                  0.0.0.0:3000->80/tcp, [::]:3000->80/tcp
streetcode-node-exporter   prom/node-exporter:v1.6.0                    "/bin/node_exporter …"   node-exporter      Up About a minute             0.0.0.0:9100->9100/tcp, [::]:9100->9100/tcp
streetcode-prometheus      prom/prometheus:v2.45.0                      "/bin/prometheus --c…"   prometheus         Up About a minute             0.0.0.0:9090->9090/tcp, [::]:9090->9090/tcp
streetcode-redis           redis:7-alpine                               "docker-entrypoint.s…"   redis              Up About a minute (healthy)   0.0.0.0:6379->6379/tcp, [::]:6379->6379/tcp

```

### 2. Jenkins Console Log Excerpt (Pipeline Build #39)

```text
01:33:54  Checking GitHub Actions (SonarCloud, Snyk & Trivy) status for commit: 92ebe91c19f4...
01:33:57  ✅ All GitHub CI checks verified successfully. Proceeding with tests and deployment...
...
01:39:31  Logging in to GitHub Container Registry...
01:39:34  Login Succeeded
01:39:36  39: digest: sha256:5216154ed182039 size: 1789
01:39:41  39: digest: sha256:9686d1c1a3242b7 size: 2201
...
01:39:44  Waiting for Prometheus...
01:39:44  Prometheus Server is Healthy.
01:39:44  Waiting for Grafana...
01:39:45  {
01:39:45    "commit": "81d85ce802",
01:39:45    "database": "ok",
01:39:45    "version": "10.0.0"
01:39:45  }
01:39:45  ✅ All monitoring services are fully healthy!
...
01:39:46  + curl -fsS --retry 10 --retry-delay 3 http://host.docker.internal:3000/
01:39:46  ✅ Frontend is accessible on port 3000!
01:39:49  ✅ Pipeline finished successfully: Tests passed, application deployed via Ansible, and artifacts pushed to GHCR!

Finished: SUCCESS

```

---

## Conclusions

* **Multi-Layered CI/CD Security Auditing:** The pipeline performs automated static code analysis (**SonarCloud**), dependency auditing (**Snyk**), and container image scanning (**Trivy**) before deployment. Snyk and Trivy run in **audit/reporting mode** (`continue-on-error: true`, `exit-code: '0'`): findings are reported but do not fail the build. The Jenkins gate only confirms that all three scans executed successfully, not that no vulnerabilities were found.
* **Automated Registry Lifecycle:** Images built during the Jenkins/Ansible deployment are tagged (`:${BUILD_NUMBER}`, `:latest`) and published to **GHCR**. Trivy scans images built from the same Dockerfiles and commit in GitHub Actions; since they are built separately, scanning the exact images pushed to GHCR is a possible future improvement.
* **Full Infrastructure Observability:** Deployments include a **Prometheus + Grafana + Node Exporter + cAdvisor** stack with an automated health check stage in Jenkins.
* **End-to-End Automation:** The pipeline automates testing, non-blocking security auditing, building, publishing, deployment, monitoring verification, and smoke testing.
