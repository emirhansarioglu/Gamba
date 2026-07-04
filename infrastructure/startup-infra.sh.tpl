#!/bin/bash
set -euxo pipefail

AR_HOST="${artifact_registry_host}"
FRONTEND_IMAGE="${frontend_image}"
NGINX_IMAGE="${nginx_image}"
POSTGRES_IMAGE="${postgres_image}"
REDIS_IMAGE="${redis_image}"
ENABLE_OBSERVABILITY="${enable_observability}"
PROMETHEUS_IMAGE="${prometheus_image}"
GRAFANA_IMAGE="${grafana_image}"

mkdir -p /mnt/stateful_partition/gamba/postgres
mkdir -p /mnt/stateful_partition/gamba/redis
mkdir -p /mnt/stateful_partition/gamba/nginx
mkdir -p /mnt/stateful_partition/gamba/prometheus
mkdir -p /mnt/stateful_partition/gamba/grafana/provisioning/datasources
mkdir -p /mnt/stateful_partition/gamba/grafana/provisioning/dashboards
mkdir -p /mnt/stateful_partition/gamba/grafana/dashboards
mkdir -p /mnt/stateful_partition/gamba/docker-config

allow_input_port() {
  local port="$1"
  iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
}

allow_input_port 80
allow_input_port 5432
allow_input_port 6379
if [[ "$ENABLE_OBSERVABILITY" == "true" ]]; then
  allow_input_port 3000
  allow_input_port 9090
fi

export DOCKER_CONFIG=/mnt/stateful_partition/gamba/docker-config
docker-credential-gcr configure-docker --registries "$AR_HOST"

docker pull "$POSTGRES_IMAGE"
docker pull "$REDIS_IMAGE"
docker pull "$FRONTEND_IMAGE"
docker pull "$NGINX_IMAGE"
if [[ "$ENABLE_OBSERVABILITY" == "true" ]]; then
  docker pull "$PROMETHEUS_IMAGE"
  docker pull "$GRAFANA_IMAGE"
fi

docker rm -f gamba-postgres || true
docker run -d \
  --name gamba-postgres \
  --restart unless-stopped \
  -e POSTGRES_USER=gamba \
  -e POSTGRES_PASSWORD=gamba \
  -e POSTGRES_DB=gamba \
  -p 5432:5432 \
  -v /mnt/stateful_partition/gamba/postgres:/var/lib/postgresql/data \
  "$POSTGRES_IMAGE"

docker rm -f gamba-redis || true
docker run -d \
  --name gamba-redis \
  --restart unless-stopped \
  -p 6379:6379 \
  -v /mnt/stateful_partition/gamba/redis:/data \
  "$REDIS_IMAGE" \
  redis-server --appendonly yes

if [[ "$ENABLE_OBSERVABILITY" == "true" ]]; then
  cat > /mnt/stateful_partition/gamba/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: gamba-backend
    metrics_path: /metrics
    static_configs:
      - targets:
%{ for ip in backend_ips ~}
          - ${ip}:8000
%{ endfor ~}
EOF

  cat > /mnt/stateful_partition/gamba/grafana/provisioning/datasources/prometheus.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    uid: Prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: true
EOF

  cat > /mnt/stateful_partition/gamba/grafana/provisioning/dashboards/gamba.yml <<'EOF'
apiVersion: 1

providers:
  - name: Gamba
    orgId: 1
    folder: Gamba
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF

  cat > /mnt/stateful_partition/gamba/grafana/dashboards/gamba-load-testing.json <<'EOF'
${grafana_dashboard_json}
EOF

  docker rm -f gamba-prometheus || true
  docker run -d \
    --name gamba-prometheus \
    --restart unless-stopped \
    --network host \
    -v /mnt/stateful_partition/gamba/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
    "$PROMETHEUS_IMAGE" \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --web.listen-address=:9090

  docker rm -f gamba-grafana || true
  docker run -d \
    --name gamba-grafana \
    --restart unless-stopped \
    --network host \
    -e GF_SERVER_HTTP_ADDR=0.0.0.0 \
    -e GF_SERVER_HTTP_PORT=3000 \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    -e GF_AUTH_ANONYMOUS_ENABLED=true \
    -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
    -v /mnt/stateful_partition/gamba/grafana/provisioning:/etc/grafana/provisioning:ro \
    -v /mnt/stateful_partition/gamba/grafana/dashboards:/var/lib/grafana/dashboards:ro \
    "$GRAFANA_IMAGE"
else
  docker rm -f gamba-prometheus || true
  docker rm -f gamba-grafana || true
fi

docker rm -f gamba-frontend || true
docker run -d \
  --name gamba-frontend \
  --restart unless-stopped \
  -p 127.0.0.1:5173:80 \
  "$FRONTEND_IMAGE"

cat > /mnt/stateful_partition/gamba/nginx/nginx.conf <<'EOF'
events {}

http {
  upstream backend_pool {
%{ for ip in backend_ips ~}
    server ${ip}:8000 max_fails=3 fail_timeout=10s;
%{ endfor ~}
  }

  server {
    listen 80;

    location /health {
      proxy_pass http://backend_pool;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /metrics {
      proxy_pass http://backend_pool;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /api/ {
      proxy_pass http://backend_pool;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /docs {
      proxy_pass http://backend_pool;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /openapi.json {
      proxy_pass http://backend_pool;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
      proxy_pass http://127.0.0.1:5173;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
  }
}
EOF

docker rm -f gamba-nginx || true
docker run -d \
  --name gamba-nginx \
  --restart unless-stopped \
  --network host \
  -v /mnt/stateful_partition/gamba/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  "$NGINX_IMAGE"
