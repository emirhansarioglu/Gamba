#!/bin/bash
set -euxo pipefail

AR_HOST="${artifact_registry_host}"
FRONTEND_IMAGE="${frontend_image}"
NGINX_IMAGE="${nginx_image}"
POSTGRES_IMAGE="${postgres_image}"
REDIS_IMAGE="${redis_image}"

mkdir -p /mnt/stateful_partition/gamba/postgres
mkdir -p /mnt/stateful_partition/gamba/redis
mkdir -p /mnt/stateful_partition/gamba/nginx
mkdir -p /mnt/stateful_partition/gamba/docker-config

allow_input_port() {
  local port="$1"
  iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
}

allow_input_port 80
allow_input_port 5432
allow_input_port 6379

export DOCKER_CONFIG=/mnt/stateful_partition/gamba/docker-config
docker-credential-gcr configure-docker --registries "$AR_HOST"

docker pull "$POSTGRES_IMAGE"
docker pull "$REDIS_IMAGE"
docker pull "$FRONTEND_IMAGE"
docker pull "$NGINX_IMAGE"

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
