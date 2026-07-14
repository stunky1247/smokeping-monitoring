# SmokePing Network Performance Monitoring

A portable, containerized SmokePing monitoring node optimized for high-resolution tracking of gaming networks, content delivery nodes (CDNs), and core internet services. This repository maintains infrastructure configurations separately from tracking data history.

---

## 📋 Table of Contents
1. [Background & Use Cases](#-background--use-cases)
2. [Monitored Infrastructure Layout](#-monitored-infrastructure-layout)
3. [Quick Start](#-quick-start)
4. [High-Resolution Configurations](#-high-resolution-configurations)
5. [Useful CLI Commands & Diagnostics](#-useful-cli-commands--diagnostics)
6. [Official Documentation](#-official-documentation)

---

## 🧠 Background & Use Cases
[SmokePing](https://oetiker.ch) measures network latency, jitter, and packet loss over time. Unlike basic ping utilities, SmokePing displays metrics using "smokey" variance bars that visually distinguish steady latency from erratic connections.

### Why this setup tracks Roblox via Curl (HTTP/HTTPS)
Roblox game servers process real-time interactions over UDP ports, while asset loading, marketplace tools, and client verification pass over standard web infrastructure. Standard ICMP pings fail or are blocked by cloud edge endpoints. This architecture deploys a customized `Curl` probe to track full web handshakes over port 443 against the distributed Roblox load-balancing infrastructure.

---

## 🗺️ Monitored Infrastructure Layout
Under the **Roblox Services** dashboard menu, this engine isolates latency anomalies across four distinct infrastructure points:
* **Web Portal (`://roblox.com`)**: Baseline accessibility to the main user web client and home dashboards.
* **Core API (`://roblox.com`)**: Backend database microservices handling login processing and endpoint profiles.
* **CDN Static Assets (`://rbxcdn.com`)**: Administrative content nodes serving icons, structural text, and layout data.
* **CDN Game Assets (`://roblox.com`)**: High-throughput distributed nodes rendering game file maps, avatar meshes, and clothing textures.

---

## 🚀 Quick Start

### Prerequisites
* [Docker and Docker Compose](https://docker.com) installed on the host system.
* Proper system execution privileges (`UID=1000`/`GID=1000`).

### Starting the Service
From the repository root folder, launch the containerized application detached in the background:
```bash
docker compose up -d
```
The web dashboard is instantly exposed on the host mapping port at `http://localhost:80/smokeping.cgi`.

### Stopping the Service
To temporarily pause network probing without losing historical data files:
```bash
docker compose down
```

---

## ⏱️ High-Resolution Configurations
This deployment overrides SmokePing's default conservative 5-minute sampling structure to collect high-fidelity data points:
* **Step Interval**: `60 seconds` (Reduces sampling granularity from 5 minutes to 1 minute).
* **Pings Per Step**: `20 requests` (Generates deeper statistical averaging against jitter anomalies).

> [!IMPORTANT]
> **Database Incompatibility Constraint:** SmokePing writes performance histories to static, fixed-size `.rrd` (Round Robin Database) file headers. If you alter the `step` or `pings` configuration properties inside `./smokeping/config/Database`, the system engine will fail to start due to structural mismatch errors.
> To resolve configuration mismatch adjustments, you must flush the existing cache layers entirely:
> ```bash
> docker compose down
> rm -f ./smokeping/data/**/*.rrd
> docker compose up -d
> ```

---

## 🛠️ Useful CLI Commands & Diagnostics

### Live Logging Triage
To track active service hooks, engine setups, probe forks, or configuration parser issues:
```bash
docker logs -f smokeping
```

### Resetting Web Cache Trees
If targets are renamed or dropped in `./smokeping/config/Targets` while a browser holds an active connection state, SmokePing might display a page crash warning. Clear the client-side DOM structure by forcing a hard cache reload inside your browser tab:
* **Windows / Linux**: `Ctrl + F5`
* **macOS**: `Cmd + Shift + R`

---

## 📚 Official Documentation
For deep-dive optimizations, structural layout adjustments, and alert rule parsing guidelines, reference the official documentation sites:
* **Official SmokePing Homepage**: [oss.oetiker.ch/smokeping](https://oetiker.ch)
* **SmokePing Configuration Parameter Matrix**: [oss.oetiker.ch/smokeping/doc/smokeping_config.en.html](https://oetiker.chdoc/smokeping_config.en.html)
* **LinuxServer.io Container Maintenance Manual**: [docs.linuxserver.io/images/docker-smokeping](https://linuxserver.io)
