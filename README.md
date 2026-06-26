# Gamba
A sport event application developed for a scalable engineering project 

## Overview

Gamba is a web-only sports venue booking application. Players can browse and join open sports events in European cities. Organizers can create events at specific venues, times, and skill levels. The app is also the subject of a scalability engineering assignment, so the architecture is designed to demonstrate stateless/stateful separation, horizontal scaling, overload mitigation, caching, and observability.

---

## Tech Stack

| Layer | Choice |
|---|---|
| Frontend | React + Vite (web only, served as static files) |
| Backend | Python FastAPI |
| Database | PostgreSQL (single node, not scaled) |
| Cache | Redis (single node) |
| Load Balancer | Nginx (manual round-robin in front of backend nodes) |
| Infrastructure | Terraform on GCP Compute Engine |
| Load Testing | K6 |

---

## Architecture

```
[React Frontend — static files served by Nginx]
                    |
         [Nginx Load Balancer VM]
          /          |          \
    [FastAPI]    [FastAPI]    [FastAPI]   ← 1 / 3 / 5 nodes (scaled component)
          \          |          /
           [PostgreSQL VM]   [Redis VM]
```

Backend nodes are **stateless** — they hold no local state between requests. All persistent state lives in PostgreSQL. Redis is a shared cache layer. This satisfies the stateless/stateful separation requirement.

---

## Scalability Requirements Mapping

| # | Requirement | Implementation |
|---|---|---|
| 1 | Stateless + stateful separation | FastAPI nodes = stateless; PostgreSQL = stateful |
| 2 | Scale 1 → 3 → 5 nodes | `backend_node_count` Terraform variable; Nginx round-robins across nodes |
| 3 | Overload mitigation | Hand-rolled **token bucket rate limiter** as FastAPI middleware (no library) |
| 4a | Additional strategy 1 | **Redis caching** — cache `GET /events` responses, 30s TTL, invalidated on writes |
| 4b | Additional strategy 2 | **Observability** — Prometheus `/metrics` endpoint + structured JSON logging |

---

## Project Structure

```
gamba/
├── frontend/
│   ├── src/
│   │   ├── main.jsx
│   │   ├── App.jsx
│   │   ├── pages/
│   │   │   ├── Login.jsx             # Username/password + role selector + register toggle
│   │   │   ├── OrganizerView.jsx     # Create event form
│   │   │   └── PlayerView.jsx        # Browse + join events
│   │   └── api.js                    # Axios wrapper with JWT header injection
│   ├── index.html
│   └── package.json
├── backend/
│   ├── main.py                       # FastAPI app, CORS, lifespan hooks
│   ├── routers/
│   │   ├── auth.py                   # /register, /login
│   │   └── events.py                 # CRUD routes
│   ├── middleware/
│   │   └── rate_limiter.py           # Token bucket, in-memory per IP
│   ├── auth_utils.py                 # bcrypt verify, JWT encode/decode
│   ├── cache.py                      # Redis get/set/delete helpers
│   ├── metrics.py                    # Prometheus counters + histograms
│   ├── database.py                   # SQLAlchemy engine + session
│   ├── models.py                     # SQLAlchemy ORM models
│   ├── schemas.py                    # Pydantic request/response schemas
│   └── requirements.txt
├── infrastructure/
│   ├── main.tf                       # VMs, VPC, firewall rules
│   ├── variables.tf                  # backend_node_count, machine_type, region
│   ├── nginx.conf.tpl                # Nginx upstream template (filled by Terraform)
│   └── outputs.tf
├── scripts/
│   ├── bootstrap.sh                  # Install Python, Node, Nginx, etc. on a fresh VM
│   ├── deploy.sh                     # Build frontend, push code, restart services on all VMs
│   └── load_test.js                  # K6 script
└── README.md
```

---

## Data Model

### `users` table

```
id           SERIAL PRIMARY KEY
username     VARCHAR(100) UNIQUE NOT NULL
password     VARCHAR(255) NOT NULL          -- bcrypt hash, never stored plain
role         VARCHAR(20) NOT NULL           -- 'player' | 'organizer'
created_at   TIMESTAMP DEFAULT NOW()
```

### `events` table

```
id           SERIAL PRIMARY KEY
city         VARCHAR(100) NOT NULL
address      TEXT NOT NULL
sport        VARCHAR(50) NOT NULL
level        INTEGER NOT NULL               -- 1 to 5
event_time   TIMESTAMP NOT NULL
capacity     INTEGER NOT NULL
joined_count INTEGER NOT NULL DEFAULT 0
created_at   TIMESTAMP DEFAULT NOW()
```

---

## Authentication

### Flow

1. A new user hits the login screen, toggles to "Register", fills in username, password, and selects a role (Player or Organizer), and submits.
2. The backend hashes the password with bcrypt and stores the user row.
3. On login, the backend verifies the bcrypt hash and returns a **JWT** containing `{user_id, username, role}`.
4. The frontend stores the JWT in `localStorage` and injects it as `Authorization: Bearer <token>` on every subsequent request via an Axios interceptor.
5. Protected endpoints decode the JWT, verify the signature, and check the role. No session state is held on the server.

### New Endpoints

```
POST /api/auth/register   body: {username, password, role}   → 201 {username, role}
POST /api/auth/login      body: {username, password}         → 200 {access_token, role}
```

### Authorization Rules

| Endpoint | Allowed roles |
|---|---|
| `GET /api/events` | player, organizer |
| `POST /api/events` | organizer only (403 otherwise) |
| `POST /api/events/{id}/join` | player only (403 otherwise) |

### New Backend Files

- `routers/auth.py` — register and login route handlers
- `auth_utils.py` — `hash_password()`, `verify_password()`, `create_token()`, `decode_token()`

### New Dependencies

```
passlib[bcrypt]
python-jose[cryptography]
python-multipart
```

---

## API Endpoints

```
GET  /health
     → {status: "ok", node_id: "<hostname>"}

GET  /metrics
     → Prometheus text format (no auth required)

POST /api/auth/register
     body: {username, password, role}
     → 201 {username, role}

POST /api/auth/login
     body: {username, password}
     → 200 {access_token, role}

GET  /api/events?city=X&sport=Y&day=YYYY-MM-DD
     → cached in Redis (key = "events:{city}:{sport}:{day}", TTL 30s)
     → list of event objects

POST /api/events
     auth: organizer JWT required
     body: {city, address, sport, level, event_time, capacity}
     → 201 event object
     → invalidates Redis keys matching city/sport/day of the new event

POST /api/events/{id}/join
     auth: player JWT required
     → 200 {joined_count, capacity}
     → 409 if event is full
     → invalidates Redis key for that event's city/sport/day
```

---

## Frontend Screens

### Login (`/`)

- Toggle between **Login** and **Register**
- Register: username, password, role selector (Player | Organizer)
- Login: username, password
- On success: JWT + role stored, routed to the correct dashboard

### Organizer Dashboard (`/organizer`)

Form fields:
- **City**: dropdown of ~20 European cities (Berlin, Paris, Amsterdam, Madrid, Rome, etc.)
- **Address**: free text input
- **Sport**: scrollable select — Football, Basketball, Tennis, Volleyball, Badminton
- **Level**: scrollable select — 1, 2, 3, 4, 5
- **Time**: scrollable select — one slot per hour for the next 3 days (72 options)
- **Capacity**: scrollable select — 2 to 50

Submit → `POST /api/events` → success toast shown.

### Player Dashboard (`/player`)

- Filter bar: city dropdown, sport dropdown, day picker (today / tomorrow / day after)
- Calls `GET /api/events` on filter change
- Event cards show: sport badge, address, level badge, time, "X spots left"
- **Join** button → `POST /api/events/{id}/join` → spots count updates in place
- Button disabled and labeled "Full" when `joined_count >= capacity`

---

## Rate Limiter (Requirement #3)

Implemented in `middleware/rate_limiter.py` as a Starlette middleware:

- **Algorithm**: Token bucket per IP address
- **Bucket size**: 60 tokens
- **Refill rate**: 1 token per second
- **On request**: consume 1 token; if bucket is empty → return `429 Too Many Requests`
- **Storage**: in-memory dict (per-process) — nodes do not share rate limit state; this is a documented known limitation
- A Prometheus counter is incremented on each 429 response

---

## Redis Caching (Requirement #4a)

Implemented in `cache.py`:

- Cache key format: `events:{city}:{sport}:{day}`
- TTL: 30 seconds
- `GET /api/events` → check Redis → **hit**: return cached JSON; **miss**: query PostgreSQL, store in Redis, return result
- `POST /api/events` (create) and `POST /api/events/{id}/join` → delete the matching Redis key
- Prometheus counters: `gamba_cache_hits_total`, `gamba_cache_misses_total`

---

## Observability (Requirement #4b)

### Prometheus Metrics (`/metrics`)

Exposed via `metrics.py`:

```
gamba_requests_total{method, endpoint, status}     -- request counter
gamba_request_duration_seconds{endpoint}           -- response time histogram
gamba_cache_hits_total                             -- Redis cache hits
gamba_cache_misses_total                           -- Redis cache misses
gamba_rate_limited_total                           -- 429 responses served
```

### Structured Logging

Python `logging` with a custom JSON formatter outputs one line per request:

```json
{"timestamp": "...", "level": "INFO", "node_id": "backend-1", "method": "GET", "path": "/api/events", "status": 200, "duration_ms": 12}
```

---

## Infrastructure (Terraform)

### Key Variables

```hcl
variable "backend_node_count" { default = 1 }   // set to 1, 3, or 5
variable "machine_type"        { default = "e2-medium" }
variable "region"              { default = "europe-west3" }  // Frankfurt
```

### Resources

| VM | Count | Purpose |
|---|---|---|
| `nginx-lb` | 1 | Nginx load balancer, public IP |
| `backend-N` | 1 / 3 / 5 | FastAPI app servers |
| `postgres-db` | 1 | PostgreSQL database |
| `redis-cache` | 1 | Redis cache |

### Firewall Rules

- Port 80: public → `nginx-lb`
- Port 8000: `nginx-lb` → `backend-*` (internal only)
- Port 5432: `backend-*` → `postgres-db` (internal only)
- Port 6379: `backend-*` → `redis-cache` (internal only)

Nginx config is generated from `nginx.conf.tpl` with backend VM IPs injected by Terraform. `deploy.sh` runs `terraform apply -var backend_node_count=N`, then SSHs into each VM to pull the latest code and restart the FastAPI service.

---

## Load Testing (K6)

`scripts/load_test.js` runs two scenarios:

1. **Read-heavy**: ramp 10 → 100 → 500 VUs hitting `GET /api/events?city=Berlin&sport=Football&day=<today>`
2. **Mixed**: 50% reads (`GET /api/events`), 50% joins (`POST /api/events/{id}/join`)

Run against each configuration (1, 3, 5 backend nodes) and record:
- Requests/second (throughput)
- p95 response latency
- Error rate (429s, 5xx)

Results go on one slide for the presentation.

---

## Known Limitations to Document

1. **Rate limiter is per-process**: each backend node has its own in-memory bucket per IP. A client could make 60 req/s × N nodes before hitting a limit. A production system would use a shared Redis counter.
2. **Redis is a single point of failure**: no replication. If the Redis VM goes down, all cache misses hit PostgreSQL directly.
3. **Cache invalidation is key-level**: deleting `events:{city}:{sport}:{day}` only clears that exact combination. A new event in Berlin for Sunday football won't invalidate a cached query for "all sports in Berlin on Sunday".
4. **No token expiry**: JWTs do not expire. A production system would add short-lived access tokens and refresh tokens.
5. **Passwords in DB**: plain bcrypt, no salting beyond what bcrypt provides internally, no pepper. Sufficient for a prototype.

---

## Dev Prerequisites (Fresh Machine)

Complete these steps in order before starting development.

### 1. Homebrew (macOS package manager)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Git

```bash
brew install git
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

### 3. Node.js (via nvm)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.zshrc
nvm install 20
nvm use 20
node --version   # should print v20.x.x
```

### 4. Python 3.11+

```bash
brew install python@3.11
python3 --version   # should print 3.11.x or higher
```

### 5. Docker Desktop

Download and install from: https://www.docker.com/products/docker-desktop/

After installation:

```bash
docker --version        # verify install
docker compose version  # verify compose plugin
```

Docker is used to run PostgreSQL and Redis locally during development without installing them natively.

### 6. Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform --version   # should print 1.x.x
```

### 7. Google Cloud SDK

```bash
brew install --cask google-cloud-sdk
gcloud init                   # follow prompts: log in, pick project
gcloud auth application-default login
gcloud --version
```

### 8. K6 (load testing)

```bash
brew install k6
k6 version
```

### 9. Local dev environment (Docker Compose)

Create a `docker-compose.dev.yml` at the project root to spin up PostgreSQL and Redis locally:

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: gamba
      POSTGRES_PASSWORD: gamba
      POSTGRES_DB: gamba
    ports:
      - "5432:5432"

  redis:
    image: redis:7
    ports:
      - "6379:6379"
```

Start with:

```bash
docker compose -f docker-compose.dev.yml up -d
```

### 10. Backend dev setup

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload   # starts on http://localhost:8000
```

### 11. Frontend dev setup

```bash
cd frontend
npm install
npm run dev   # starts on http://localhost:5173
```

### Quick verification checklist

```bash
node --version       # v20+
python3 --version    # 3.11+
docker --version     # any recent
terraform --version  # 1.x
gcloud --version     # any recent
k6 version           # any recent
```
