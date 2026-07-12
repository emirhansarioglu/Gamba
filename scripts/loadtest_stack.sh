#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/loadtest_stack.sh 1 [--detach]
  scripts/loadtest_stack.sh 3 [--detach]
  scripts/loadtest_stack.sh 5 [--detach]
  scripts/loadtest_stack.sh up <1|3|5> [--detach]
  scripts/loadtest_stack.sh down
  scripts/loadtest_stack.sh ps

Starts the local load-test stack with explicit Nginx upstreams for 1, 3, or 5 backend nodes.

After the stack is running, execute the load test with:
  k6 run -e BASE_URL=http://localhost:8000 -e TARGET_VUS=1000 scripts/load_test.js

URLs:
  App/LB:     http://localhost:8000
  Prometheus: http://localhost:9090
  Grafana:    http://localhost:3000
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.loadtest.yml"
PROJECT_NAME="gamba-loadtest"

ACTION="${1:-}"
NODE_COUNT="${2:-}"
DETACH=""

if [[ -z "$ACTION" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$ACTION" =~ ^(1|3|5)$ ]]; then
  NODE_COUNT="$ACTION"
  ACTION="up"
fi

if [[ "${2:-}" == "--detach" || "${2:-}" == "-d" || "${3:-}" == "--detach" || "${3:-}" == "-d" ]]; then
  DETACH="-d"
fi

compose_base() {
  docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

compose_all_profiles() {
  compose_base --profile nodes5 "$@"
}

case "$ACTION" in
  up)
    case "$NODE_COUNT" in
      1|3|5) ;;
      *)
        echo "node count must be 1, 3, or 5" >&2
        usage
        exit 1
        ;;
    esac

    PROFILE="nodes${NODE_COUNT}"
    export NGINX_CONFIG="nginx-loadtest-${NODE_COUNT}.conf"
    export PROMETHEUS_CONFIG="prometheus-loadtest-${NODE_COUNT}.yml"

    echo "==> Starting local load-test stack with ${NODE_COUNT} backend node(s)"
    echo "==> Nginx config:      observability/${NGINX_CONFIG}"
    echo "==> Prometheus config: observability/${PROMETHEUS_CONFIG}"
    echo "==> Removing previous gamba-loadtest stack, if any"
    compose_all_profiles down --remove-orphans

    echo "==> Building and starting containers"
    if [[ -n "$DETACH" ]]; then
      compose_base --profile "$PROFILE" up --build --force-recreate -d
      echo ""
      compose_base --profile "$PROFILE" ps
      echo ""
      echo "Run load test: k6 run -e BASE_URL=http://localhost:8000 -e TARGET_VUS=1000 scripts/load_test.js"
    else
      compose_base --profile "$PROFILE" up --build --force-recreate
    fi
    ;;
  down)
    compose_all_profiles down --remove-orphans
    ;;
  ps)
    compose_all_profiles ps
    ;;
  *)
    echo "unknown action: $ACTION" >&2
    usage
    exit 1
    ;;
esac
