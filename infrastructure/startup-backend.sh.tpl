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
TRUST_FORWARDED_IPS=${trust_forwarded_ips}
LOAD_SHEDDING_ENABLED=${load_shedding_enabled}
IN_FLIGHT_SOFT_LIMIT=${in_flight_soft_limit}
IN_FLIGHT_HARD_LIMIT=${in_flight_hard_limit}
MAX_AVG_LATENCY_MS=${max_avg_latency_ms}
LATENCY_SHED_PROBABILITY=${latency_shed_probability}
LATENCY_EWMA_ALPHA=${latency_ewma_alpha}
MAX_PROCESS_CPU_PERCENT=${max_process_cpu_percent}
CPU_SHED_PROBABILITY=${cpu_shed_probability}
CPU_EWMA_ALPHA=${cpu_ewma_alpha}
CPU_SAMPLE_INTERVAL_SECONDS=${cpu_sample_interval_seconds}
MAX_SHED_PROBABILITY=${max_shed_probability}
EOF

docker pull "$BACKEND_IMAGE"

docker rm -f gamba-backend || true
docker run -d \
  --name gamba-backend \
  --restart unless-stopped \
  --env-file /mnt/stateful_partition/gamba/backend.env \
  -p 8000:8000 \
  "$BACKEND_IMAGE"
