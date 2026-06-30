#!/usr/bin/env bash
# Deploy Gamba to GCP.
# Run from the project root after `terraform apply` and bootstrap.sh.
# Usage: bash scripts/deploy.sh [zone]
set -euo pipefail

ZONE=${1:-europe-west3-a}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
INFRA_DIR="${ROOT_DIR}/infrastructure"

# ── Read Terraform outputs ────────────────────────────────────────────────────
echo "==> Reading Terraform outputs"
cd "${INFRA_DIR}"
LB_IP=$(terraform output -raw lb_ip)
INFRA_IP=$(terraform output -raw infra_ip)
mapfile -t BACKEND_IPS < <(terraform output -json backend_ips | python3 -c "import json,sys; [print(ip) for ip in json.load(sys.stdin)]")
cd "${ROOT_DIR}"

echo "    Infra VM: ${LB_IP} (public) / ${INFRA_IP} (internal)"
echo "    Backends: ${#BACKEND_IPS[@]} node(s)"

# ── Build frontend ────────────────────────────────────────────────────────────
echo "==> Building frontend (API → http://${LB_IP})"
cd "${ROOT_DIR}/frontend"
VITE_API_URL="http://${LB_IP}" npm run build
cd "${ROOT_DIR}"

# ── Deploy frontend static files to infra VM ─────────────────────────────────
echo "==> Copying frontend to infra VM"
gcloud compute ssh "gamba@infra" --zone="${ZONE}" \
  --command="sudo mkdir -p /var/www/gamba && sudo chown gamba /var/www/gamba"
gcloud compute scp --recurse "${ROOT_DIR}/frontend/dist/." \
  "gamba@infra:/var/www/gamba/" --zone="${ZONE}"

# ── Push Nginx config and reload ──────────────────────────────────────────────
echo "==> Configuring Nginx"
gcloud compute scp "${INFRA_DIR}/nginx.conf" \
  "gamba@infra:/tmp/gamba_nginx.conf" --zone="${ZONE}"
gcloud compute ssh "gamba@infra" --zone="${ZONE}" --command="
  sudo cp /tmp/gamba_nginx.conf /etc/nginx/sites-available/gamba
  sudo ln -sf /etc/nginx/sites-available/gamba /etc/nginx/sites-enabled/gamba
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t && sudo systemctl reload nginx
"

# ── Deploy backend to each node ───────────────────────────────────────────────
for i in "${!BACKEND_IPS[@]}"; do
  INSTANCE="backend-$((i + 1))"
  echo "==> Deploying to ${INSTANCE}"

  gcloud compute ssh "gamba@${INSTANCE}" --zone="${ZONE}" \
    --command="mkdir -p /home/gamba/gamba"

  gcloud compute scp --recurse "${ROOT_DIR}/backend/." \
    "gamba@${INSTANCE}:/home/gamba/gamba/" --zone="${ZONE}"

  # Write .env — both DATABASE_URL and REDIS_URL point to the infra VM's internal IP
  gcloud compute ssh "gamba@${INSTANCE}" --zone="${ZONE}" --command="
    cat > /home/gamba/gamba/.env << 'ENVEOF'
DATABASE_URL=postgresql://gamba:gamba@${INFRA_IP}:5432/gamba
REDIS_URL=redis://${INFRA_IP}:6379
JWT_SECRET_KEY=gamba-production-secret
ALLOWED_ORIGINS=http://${LB_IP}
ENVEOF

    cd /home/gamba/gamba
    python3 -m venv .venv
    .venv/bin/pip install -q -r requirements.txt

    if ! sudo systemctl list-units --full -all | grep -q 'gamba.service'; then
      sudo bash -c 'cat > /etc/systemd/system/gamba.service << EOF
[Unit]
Description=Gamba FastAPI
After=network.target

[Service]
User=gamba
WorkingDirectory=/home/gamba/gamba
EnvironmentFile=/home/gamba/gamba/.env
ExecStart=/home/gamba/gamba/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF'
      sudo systemctl daemon-reload
      sudo systemctl enable gamba
    fi
    sudo systemctl restart gamba
  "
done

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "==> Deployment complete!"
echo "    App:     http://${LB_IP}"
echo "    Health:  curl http://${LB_IP}/health"
echo "    Metrics: curl http://${LB_IP}/metrics"
