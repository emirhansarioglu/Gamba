#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/deploy.sh <project_id> [backend_node_count] [machine_type] [image_tag]

Examples:
  scripts/deploy.sh my-gcp-project 1 e2-micro dev
  scripts/deploy.sh my-gcp-project 3 e2-micro dev
  scripts/deploy.sh my-gcp-project 5 e2-standard-2 perf

This script:
  1. Creates/enables the GCP APIs and Artifact Registry repository.
  2. Builds backend image & frontend asset image locally with Docker and pushes them to Artifact Registry.
  3. Applies the Compute Engine cluster that pulls nginx, postgres, redis, backend, frontend asset image, Prometheus, and Grafana images.
  4. Serves the React frontend from the public nginx load balancer and proxies /api, /health, /metrics to the backend pool.
  5. Uses the same node-count-specific load-shedding defaults as scripts/loadtest_stack.sh.
USAGE
}

PROJECT_ID="${1:-}"
BACKEND_NODE_COUNT="${2:-1}"
MACHINE_TYPE="${3:-e2-micro}"
IMAGE_TAG="${4:-dev}"
REGION="${REGION:-europe-west3}"
ZONE="${ZONE:-europe-west3-a}"
ARTIFACT_REPO_ID="${ARTIFACT_REPO_ID:-gamba}"

if [[ -z "$PROJECT_ID" ]]; then
  usage
  exit 1
fi

case "$BACKEND_NODE_COUNT" in
  1|3|5) ;;
  *)
    echo "backend_node_count must be 1, 3, or 5" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="${ROOT_DIR}/infrastructure"

configure_load_shedding() {
  case "$BACKEND_NODE_COUNT" in
    1)
      export IN_FLIGHT_SOFT_LIMIT="${IN_FLIGHT_SOFT_LIMIT:-8}"
      export IN_FLIGHT_HARD_LIMIT="${IN_FLIGHT_HARD_LIMIT:-35}"
      export MAX_AVG_LATENCY_MS="${MAX_AVG_LATENCY_MS:-2500}"
      export LATENCY_SHED_PROBABILITY="${LATENCY_SHED_PROBABILITY:-0.15}"
      export MAX_PROCESS_CPU_PERCENT="${MAX_PROCESS_CPU_PERCENT:-85}"
      export CPU_SHED_PROBABILITY="${CPU_SHED_PROBABILITY:-0.15}"
      export MAX_SHED_PROBABILITY="${MAX_SHED_PROBABILITY:-0.30}"
      ;;
    3)
      export IN_FLIGHT_SOFT_LIMIT="${IN_FLIGHT_SOFT_LIMIT:-10}"
      export IN_FLIGHT_HARD_LIMIT="${IN_FLIGHT_HARD_LIMIT:-35}"
      export MAX_AVG_LATENCY_MS="${MAX_AVG_LATENCY_MS:-1200}"
      export LATENCY_SHED_PROBABILITY="${LATENCY_SHED_PROBABILITY:-0.5}"
      export MAX_PROCESS_CPU_PERCENT="${MAX_PROCESS_CPU_PERCENT:-150}"
      export CPU_SHED_PROBABILITY="${CPU_SHED_PROBABILITY:-0.2}"
      export MAX_SHED_PROBABILITY="${MAX_SHED_PROBABILITY:-0.95}"
      ;;
    5)
      export IN_FLIGHT_SOFT_LIMIT="${IN_FLIGHT_SOFT_LIMIT:-30}"
      export IN_FLIGHT_HARD_LIMIT="${IN_FLIGHT_HARD_LIMIT:-180}"
      export MAX_AVG_LATENCY_MS="${MAX_AVG_LATENCY_MS:-2500}"
      export LATENCY_SHED_PROBABILITY="${LATENCY_SHED_PROBABILITY:-0.1}"
      export MAX_PROCESS_CPU_PERCENT="${MAX_PROCESS_CPU_PERCENT:-255}"
      export CPU_SHED_PROBABILITY="${CPU_SHED_PROBABILITY:-0.1}"
      export MAX_SHED_PROBABILITY="${MAX_SHED_PROBABILITY:-0.30}"
      ;;
  esac

  export LOAD_SHEDDING_ENABLED="${LOAD_SHEDDING_ENABLED:-true}"
  export LATENCY_EWMA_ALPHA="${LATENCY_EWMA_ALPHA:-0.3}"
  export CPU_EWMA_ALPHA="${CPU_EWMA_ALPHA:-0.3}"
  export CPU_SAMPLE_INTERVAL_SECONDS="${CPU_SAMPLE_INTERVAL_SECONDS:-1}"
}

configure_load_shedding

TF_VARS=(
  -var="project_id=${PROJECT_ID}"
  -var="region=${REGION}"
  -var="zone=${ZONE}"
  -var="artifact_repo_id=${ARTIFACT_REPO_ID}"
  -var="backend_node_count=${BACKEND_NODE_COUNT}"
  -var="machine_type=${MACHINE_TYPE}"
  -var="image_tag=${IMAGE_TAG}"
  -var="load_shedding_enabled=${LOAD_SHEDDING_ENABLED}"
  -var="in_flight_soft_limit=${IN_FLIGHT_SOFT_LIMIT}"
  -var="in_flight_hard_limit=${IN_FLIGHT_HARD_LIMIT}"
  -var="max_avg_latency_ms=${MAX_AVG_LATENCY_MS}"
  -var="latency_shed_probability=${LATENCY_SHED_PROBABILITY}"
  -var="latency_ewma_alpha=${LATENCY_EWMA_ALPHA}"
  -var="max_process_cpu_percent=${MAX_PROCESS_CPU_PERCENT}"
  -var="cpu_shed_probability=${CPU_SHED_PROBABILITY}"
  -var="cpu_ewma_alpha=${CPU_EWMA_ALPHA}"
  -var="cpu_sample_interval_seconds=${CPU_SAMPLE_INTERVAL_SECONDS}"
  -var="max_shed_probability=${MAX_SHED_PROBABILITY}"
)

echo "==> GCP target: ${BACKEND_NODE_COUNT} backend node(s), ${MACHINE_TYPE}, image tag ${IMAGE_TAG}"
echo "==> Load shedding: in-flight ${IN_FLIGHT_SOFT_LIMIT}/${IN_FLIGHT_HARD_LIMIT}, latency ${MAX_AVG_LATENCY_MS}ms @ ${LATENCY_SHED_PROBABILITY}, CPU ${MAX_PROCESS_CPU_PERCENT}% @ ${CPU_SHED_PROBABILITY}, max shed ${MAX_SHED_PROBABILITY}"
echo ""
echo "==> Initializing Terraform"
terraform -chdir="${TF_DIR}" init

echo ""
echo "==> Creating Artifact Registry foundation"
terraform -chdir="${TF_DIR}" apply \
  -target=google_project_service.required_apis \
  -target=google_artifact_registry_repository.gamba \
  "${TF_VARS[@]}"

echo ""
echo "==> Building and pushing application images"
"${SCRIPT_DIR}/build_images.sh" "${PROJECT_ID}" "${REGION}" "${ARTIFACT_REPO_ID}" "${IMAGE_TAG}"

echo ""
echo "==> Applying ${BACKEND_NODE_COUNT}-backend-node cluster"
terraform -chdir="${TF_DIR}" apply "${TF_VARS[@]}"

INSTANCES=(infra)
for ((i = 1; i <= BACKEND_NODE_COUNT; i++)); do
  INSTANCES+=("backend-${i}")
done

echo ""
echo "==> Restarting VMs so startup scripts pull current images and Nginx sees current backends"
gcloud compute instances reset "${INSTANCES[@]}" \
  --project="${PROJECT_ID}" \
  --zone="${ZONE}" \
  --quiet

LB_IP="$(terraform -chdir="${TF_DIR}" output -raw lb_ip)"
PROMETHEUS_URL="$(terraform -chdir="${TF_DIR}" output -raw prometheus_url 2>/dev/null || true)"
GRAFANA_URL="$(terraform -chdir="${TF_DIR}" output -raw grafana_url 2>/dev/null || true)"

APP_URL="http://${LB_IP}"

echo ""
echo "==> Smoke checking public load balancer"
for attempt in {1..30}; do
  if curl -fsS "${APP_URL}/" >/dev/null && curl -fsS "${APP_URL}/health" >/dev/null; then
    echo "Frontend and backend health are reachable through nginx."
    break
  fi

  if [[ "$attempt" -eq 30 ]]; then
    echo "Warning: public nginx did not pass smoke checks yet. Startup may still be finishing." >&2
    break
  fi

  sleep 5
done

if [[ -n "$GRAFANA_URL" && "$GRAFANA_URL" != "null" ]]; then
  echo ""
  echo "==> Smoke checking Grafana"
  for attempt in {1..30}; do
    dashboard_search="$(
      curl -fsS -u admin:admin "${GRAFANA_URL}/api/search?query=Gamba%20Load%20Testing" 2>/dev/null || true
    )"

    if curl -fsS "${GRAFANA_URL}/api/health" >/dev/null && [[ "$dashboard_search" == *"Gamba Load Testing"* ]]; then
      echo "Grafana health and Gamba dashboard are reachable."
      break
    fi

    if [[ "$attempt" -eq 30 ]]; then
      echo "Warning: Grafana did not pass smoke checks yet. Startup may still be finishing." >&2
      break
    fi

    sleep 5
  done
fi

echo ""
echo "==> Deployment complete"
echo "App:        ${APP_URL}"
echo "Frontend:   ${APP_URL}/"
echo "API:        ${APP_URL}/api/..."
echo "Health:     curl ${APP_URL}/health"
echo "Metrics:    curl ${APP_URL}/metrics"
echo "Run load test: k6 run -e BASE_URL=${APP_URL} -e TARGET_VUS=1000 -e AUTH_USERS=1000 -e AUTH_SETUP_BATCH_SIZE=25 -e RUN_ID=gcp${BACKEND_NODE_COUNT}_${MACHINE_TYPE}_${IMAGE_TAG} scripts/load_test.js"
if [[ -n "$PROMETHEUS_URL" && "$PROMETHEUS_URL" != "null" ]]; then
  echo "Prometheus: ${PROMETHEUS_URL}"
fi
if [[ -n "$GRAFANA_URL" && "$GRAFANA_URL" != "null" ]]; then
  echo "Grafana:    ${GRAFANA_URL}"
  echo "Grafana login: admin / admin"
fi
