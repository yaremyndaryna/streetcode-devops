# streetcode-devops
# 🐳 Docker Deployment — Streetcode DevOps

This branch contains the setup for containerizing and running the **Streetcode** project (Frontend, Backend, and MS SQL Database) using **Docker** and **Docker Compose**.

---

## 🏗 Architecture & Services

The application consists of three main services connected within a shared Docker bridge network:

| Service | Container Name | Technology | Host Port | Container Port |
| :--- | :--- | :--- | :--- | :--- |
| **Database** | `streetcode-db` | MS SQL Server 2022 | `1433` | `1433` |
| **Backend** | `streetcode-backend` | .NET 6 / ASP.NET Web API | `5000` | `5000` |
| **Frontend** | `streetcode-frontend` | React + Nginx | `3000` | `80` |

---

## ⚙️ Prerequisites

Before starting, ensure that your virtual machine or local system has:
* **Git** installed
* **Docker Engine** (>= 20.10)
* **Docker Compose** (>= v2.0)
* Free host ports: `1433`, `5000`, `3000`

---

## 🚀 Step-by-Step Installation & Run Guide

### Step 1: Clone the Repository

Clone the project repository and switch to the `docker` branch:

```bash
git clone https://github.com/yaremyndaryna/streetcode-devops.git streetcode-devops
cd streetcode-devops
git checkout docker
```
### Step 2: Configure Environment Variables

Create a `.env` file in the root directory of the project to set the database credentials, ports, and the address of the machine where the project runs:

```env
MS_SQL_DB_PORT=1433
SA_PASSWORD=YOUR_STRONG_PASSWORD
DB_USER=sa
DB_NAME=StreetcodeDb
HOST_IP=192.168.0.170
API_URL=http://${HOST_IP}:5000/api
```

> **Important:** replace `192.168.0.170` with the IP address of **your** machine, in `HOST_IP`.
>
> - To find the IP of the machine, run: `hostname -I`
> - If you open the site on the same machine where Docker runs, you can use `localhost` instead of the IP (`HOST_IP=localhost`, `API_URL=http://localhost:5000/api`).

#### What each variable does

| Variable | Description |
|---|---|
| `MS_SQL_DB_PORT` | Port on which SQL Server is exposed on the host |
| `SA_PASSWORD` | SQL Server `sa` password (must meet SQL Server complexity rules) |
| `DB_USER` | Database user (use `sa` on a fresh container) |
| `DB_NAME` | Database name, created automatically by migrations |
| `HOST_IP` | IP address of the machine, used by the backend for CORS (`http://HOST_IP:3000`) |
| `API_URL` | Backend address that the **browser** uses; it is built into the frontend at build time |

> **Note:** the API address is baked into the frontend during `docker compose build`.
> If the IP changes, update `.env` and rebuild the frontend:
> ```bash
> docker compose up -d --build frontend
> docker compose up -d backend
> ```
## Step 3: Build and Run with Docker Compose

Build the images and start all services in detached mode (`-d`):

```bash
docker compose up --build -d
```

## Step 4: Verify Running Containers

Check if all three containers are in the `Up` or `healthy` state:

```bash
docker compose ps
```
## 🌐 Application Access

Once all services are running, you can access them via your browser:

- **Frontend App:** [http://localhost:3000](http://localhost:3000)
  or `http://<YOUR_VM_IP>:3000`

- **Backend API (Swagger):** [http://localhost:5000/swagger/index.html](http://localhost:5000/swagger/index.html)
  or `http://<YOUR_VM_IP>:5000/swagger/index.html`

## 🧹 Maintenance Commands

View live logs for all services:

```bash
docker compose logs -f
```

Restart a specific service (e.g., backend):

```bash
docker compose restart backend
```

Stop running services:

```bash
docker compose down
```

Completely stop and remove containers, networks, and volumes:

```bash
docker compose down -v --remove-orphans
```