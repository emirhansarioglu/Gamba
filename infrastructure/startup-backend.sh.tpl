#!/bin/bash
set -euxo pipefail

AR_HOST="${artifact_registry_host}"
BACKEND_IMAGE="${backend_image}"

mkdir -p /mnt/stateful_partition/gamba
mkdir -p /mnt/stateful_partition/gamba/docker-config

allow_input_port() {
  local port="$1"
  iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
}

allow_input_port 8000

export DOCKER_CONFIG=/mnt/stateful_partition/gamba/docker-config
docker-credential-gcr configure-docker --registries "$AR_HOST"

cat > /mnt/stateful_partition/gamba/backend.env <<'EOF'
DATABASE_URL=${database_url}
REDIS_URL=${redis_url}
JWT_SECRET_KEY=${jwt_secret_key}
ALLOWED_ORIGINS=${allowed_origins}
EOF

docker pull "$BACKEND_IMAGE"

docker rm -f gamba-backend || true
docker run -d \
  --name gamba-backend \
  --restart unless-stopped \
  --env-file /mnt/stateful_partition/gamba/backend.env \
  -p 8000:8000 \
  "$BACKEND_IMAGE"
