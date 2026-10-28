# Load Balancing & Infrastructure Monitoring

This branch introduces an Nginx-based Load Balancing architecture, Redis session management, and a complete Monitoring Stack (Prometheus, Grafana, Node Exporter, cAdvisor) for the Streetcode web application. It distributes incoming HTTP requests across multiple frontend application replicas using the Round-Robin algorithm while providing centralized session management and real-time infrastructure and container telemetry.

---

## Architecture Overview

With the Load Balancer, Redis, and Monitoring Stack integrated, the infrastructure operates under a highly available reverse-proxy model with distributed caching and full operational visibility:

```
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
       +-------------------------+       +-------------------------+
       |  streetcode-app-1       |       |  streetcode-app-2       |
       |  (Frontend Replica 1)   |       |  (Frontend Replica 2)   |
       +-------------------------+       +-------------------------+
                               \           /
                                v         v
                    +----------------------------------+
                    | streetcode-backend (.NET Core)   |
                    +----------------------------------+
                                    |
                                    |
                                    +-----------------------------------+
                                    |                                   |
                                    v                                   v
                    +----------------------------------+ +----------------------------------+
                    |  streetcode-db (MS SQL Server)   | |     streetcode-redis (Redis 7)   |
                    +----------------------------------+ +----------------------------------+

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


### Key Changes
- **Isolation of Replicas:** Frontend containers (`streetcode-app-1`, `streetcode-app-2`) no longer publish host ports directly. They communicate strictly within the internal Docker network.
- **Single Entrypoint:** Nginx (`streetcode-lb`) is the sole service listening on port `3000` to receive public traffic.
- **Redundancy:** Traffic is dynamically distributed between both instances. If one instance fails, Nginx routes all incoming requests to the surviving instance seamlessly.
- **Session State Management via Redis:** Integrated Redis (`streetcode-redis`) as a centralized distributed cache for session management. This ensures that session state is preserved independently across backend operations, backed by persistent volume storage (`dump.rdb`) and secured via `requirepass` password authentication.
* **Full-Stack Telemetry:**
* **Prometheus:** Periodically scrapes metrics every 15 seconds from exporters.
* **Node Exporter:** Captures host-level system metrics (CPU, RAM, Disk usage, and Network I/O).
* **cAdvisor:** Provides real-time resource consumption metrics for every individual running Docker container.
* **Grafana:** Offers web-based visualization dashboards backed by persistent storage (`grafana_data`).


---


## How to Run and Verify Locally
### Step 1: Configure Environment Variables

Create a `.env` file in the root directory of the project to set the database credentials, ports, the Grafana admin password, and the address of the machine where the project runs:

```env
MS_SQL_DB_PORT=1433
SA_PASSWORD=YOUR_STRONG_PASSWORD
DB_USER=sa
DB_NAME=StreetcodeDb
REDIS_PASSWORD=YOUR_SECRET_REDIS_PASSWORD
GF_SECURITY_ADMIN_PASSWORD=YOUR_GRAFANA_ADMIN_PASSWORD
HOST_IP=192.168.0.170
API_URL=http://${HOST_IP}:5000/api
```

> **Important:** replace `192.168.0.170` with the IP address of **your** machine, in `HOST_IP`.
>
> - To find the IP of the machine, run: `hostname -I`
> - If you open the site on the same machine where Docker runs, you can use `localhost` instead of the IP (`HOST_IP=localhost`, `API_URL=http://localhost:5000/api`).

### Step 2: Start the Docker Stack

Clean up any legacy containers and run the environment:

```bash
docker compose down
docker compose up -d --build
```

### Step 3: Check Container Status

Ensure all **9 services** are running properly:

```bash
docker compose ps

```

Expected output includes:

* `streetcode-db` (healthy)
* `streetcode-redis` (healthy)
* `streetcode-backend`
* `streetcode-app-1`
* `streetcode-app-2`
* `streetcode-lb`
* `streetcode-prometheus`
* `streetcode-grafana`
* `streetcode-node-exporter`
* `streetcode-cadvisor`

### Step 4: Verify Redis Session Store Connectivity

1. Verify authentication and connectivity without exposing secrets in system logs:

To adhere to security best practices and prevent password exposure in process trees (ps aux), credentials are passed via the REDISCLI_AUTH environment variable:

```bash
docker exec -it -e REDISCLI_AUTH="$(grep REDIS_PASSWORD .env | cut -d '=' -f2)" streetcode-redis redis-cli ping
```

*Observation:* Redis responds with `PONG`.

2. Inspect keys saved in the distributed session cache:

```bash
docker exec -it -e REDISCLI_AUTH="$(grep REDIS_PASSWORD .env | cut -d '=' -f2)" streetcode-redis redis-cli
```

Inside the Redis CLI prompt:
```text
KEYS *
```

*Observation:* Returns stored session keys prefixed according to backend configuration or `(empty array)` if no stateful session operations have been triggered yet.

### Step 5: Verify Load Balancing (Round-Robin)

1. Open two terminal windows to watch logs for both application replicas:

```bash
# Terminal 1
docker logs -f streetcode-app-1

# Terminal 2
docker logs -f streetcode-app-2
```

2. Perform requests using `curl`:

```bash
curl -i http://localhost:3000/
curl -i http://localhost:3000/
```

*Observation:* The first request will log in `streetcode-app-1`, and the second request will log in `streetcode-app-2`.

### Step 6: Test Failover Capability

1. Stop the first instance:
```bash
docker stop streetcode-app-1
```

2. Send requests to the site:
```bash
curl -i http://localhost:3000/
```

*Observation:* Nginx automatically detects the offline instance and serves responses through `streetcode-app-2` without downtime.

3. Restart the instance:
```bash
docker start streetcode-app-1
```

---

## Verifying Monitoring Infrastructure

### 1. Prometheus Metrics Collector (Port 9090)

* **Web UI Access:** Open `http://<YOUR_HOST_IP>:9090` or `http://localhost:9090`.
* **Target Verification:** Navigate to **Status -> Targets** in the top navigation bar.
* **Expected Status:**
* `prometheus` (`http://localhost:9090/metrics`) — **UP**
* `node-exporter` (`http://node-exporter:9100/metrics`) — **UP**
* `cadvisor` (`http://cadvisor:8080/metrics`) — **UP**

---

### 2. Node Exporter System Metrics (Port 9100)

* **Raw Metrics Access:** `http://localhost:9100/metrics`
* Exposes Linux host metrics including `node_cpu_seconds_total`, `node_memory_MemTotal_bytes`, and `node_network_receive_bytes_total`.

---

### 3. cAdvisor Container Telemetry (Port 8082)

* **Web Interface:** Open `http://localhost:8082` to inspect real-time resource utilization graphs for each active Docker container (`streetcode-backend`, `streetcode-db`, `streetcode-lb`, etc.).
* **Raw Metrics Access:** `http://localhost:8082/metrics`

---

### 4. Grafana Visual Dashboards (Port 3001)

* **Web UI Access:** Open `http://<YOUR_HOST_IP>:3001` or `http://localhost:3001`.
* **Authentication:**
* **Username:** `admin`
* **Password:** The value assigned to `GF_SECURITY_ADMIN_PASSWORD` in your `.env` file.


* **Prometheus Data Source Integration:**
1. Go to **Connections -> Data Sources -> Add data source**.
2. Select **Prometheus**.
3. Set the Connection URL to: `http://prometheus:9090` (internal Docker network DNS).
4. Click **Save & test** (*Expected message: "Successfully queried the Prometheus API"*).


* **Import Community Dashboards:**
* **Docker Containers Dashboard (cAdvisor):** Go to **Dashboards -> New -> Import**, enter ID `14282` or `893`, and choose Prometheus as the data source.
* **Node Exporter Host Dashboard:** Import dashboard ID `1860` for comprehensive host CPU, RAM, and Disk visualizations.



---

## Testing Alternative Load-Balancing Algorithms

By default, Nginx distributes incoming traffic using the standard **Round-Robin** algorithm. You can test other distribution strategies by updating the `upstream` block in your `lb/nginx.conf` file:

---

### 1. Weighted Round-Robin
Directs more traffic to higher-capacity servers.

```nginx
upstream streetcode_app {
    server streetcode-app-1:80 weight=3; # Receives ~75% of traffic
    server streetcode-app-2:80 weight=1; # Receives ~25% of traffic
}

```

* **How to test:** Send 8 requests via browser or `curl`. You will see `streetcode-app-1` handling 3 out of every 4 requests in `docker logs`.

---

### 2. IP Hash (`ip_hash`)

Ensures requests from the same client IP address are consistently routed to the same backend container (sticky sessions).

```nginx
upstream streetcode_app {
    ip_hash;
    server streetcode-app-1:80;
    server streetcode-app-2:80;
}

```

* **How to test:** Refresh the browser multiple times. All incoming requests from your IP will land exclusively on one container (e.g., `streetcode-app-1`).

---

### 🔄 Applying Algorithm Changes

After editing `lb/nginx.conf`, restart the Nginx load balancer to apply the new settings:

```bash
docker compose restart nginx-lb

```
