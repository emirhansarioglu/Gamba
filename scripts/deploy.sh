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

TF_VARS=(
  -var="project_id=${PROJECT_ID}"
  -var="region=${REGION}"
  -var="zone=${ZONE}"
  -var="artifact_repo_id=${ARTIFACT_REPO_ID}"
  -var="backend_node_count=${BACKEND_NODE_COUNT}"
  -var="machine_type=${MACHINE_TYPE}"
  -var="image_tag=${IMAGE_TAG}"
)

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

echo ""
echo "==> Deployment complete"
echo "App:        http://${LB_IP}"
echo "Health:     curl http://${LB_IP}/health"
echo "Metrics:    curl http://${LB_IP}/metrics"
if [[ -n "$PROMETHEUS_URL" && "$PROMETHEUS_URL" != "null" ]]; then
  echo "Prometheus: ${PROMETHEUS_URL}"
fi
if [[ -n "$GRAFANA_URL" && "$GRAFANA_URL" != "null" ]]; then
  echo "Grafana:    ${GRAFANA_URL}"
  echo "Grafana login: admin / admin"
fi
