#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build_images.sh <project_id> [region] [artifact_repo_id] [image_tag]

Builds and pushes the Gamba backend image and frontend static asset image to Artifact Registry.
The Artifact Registry repository must already exist.
Requires local Docker and `gcloud auth configure-docker` access.
USAGE
}

PROJECT_ID="${1:-}"
REGION="${2:-europe-west3}"
ARTIFACT_REPO_ID="${3:-gamba}"
IMAGE_TAG="${4:-dev}"

if [[ -z "$PROJECT_ID" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_HOST="${REGION}-docker.pkg.dev"
REGISTRY_REPO="${REGISTRY_HOST}/${PROJECT_ID}/${ARTIFACT_REPO_ID}"
BACKEND_IMAGE="${REGISTRY_REPO}/gamba-backend:${IMAGE_TAG}"
FRONTEND_IMAGE="${REGISTRY_REPO}/gamba-frontend-assets:${IMAGE_TAG}"

echo "Project:        ${PROJECT_ID}"
echo "Region:         ${REGION}"
echo "Repository:     ${REGISTRY_REPO}"
echo "Backend image:  ${BACKEND_IMAGE}"
echo "Frontend asset image: ${FRONTEND_IMAGE}"

echo ""
echo "==> Configuring Docker authentication for Artifact Registry"
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet

echo ""
echo "==> Building backend image locally"
docker build --platform linux/amd64 -t "${BACKEND_IMAGE}" "${ROOT_DIR}/backend"

echo ""
echo "==> Pushing backend image"
docker push "${BACKEND_IMAGE}"

echo ""
echo "==> Building frontend static asset image locally"
docker build --platform linux/amd64 -t "${FRONTEND_IMAGE}" "${ROOT_DIR}/frontend"

echo ""
echo "==> Pushing frontend static asset image"
docker push "${FRONTEND_IMAGE}"

echo ""
echo "==> Images pushed successfully"
