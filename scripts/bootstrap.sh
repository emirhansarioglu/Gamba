#!/usr/bin/env bash
# Bootstrap a GCP VM for a specific role.
# Usage: bash scripts/bootstrap.sh <instance-name> <role> [zone]
# role: infra | backend
set -euo pipefail

INSTANCE=${1:?Usage: bootstrap.sh <instance-name> <role> [zone]}
ROLE=${2:?Usage: bootstrap.sh <instance-name> <role> [zone]}
ZONE=${3:-europe-west3-a}

ssh_run() {
  gcloud compute ssh "gamba@${INSTANCE}" --zone="${ZONE}" --command="$1"
}

echo "==> Bootstrapping ${INSTANCE} (role: ${ROLE})"
ssh_run "sudo apt-get update -qq && sudo apt-get install -y -qq curl"

case "${ROLE}" in
  infra)
    # ── Nginx ──────────────────────────────────────────────────────────────────
    ssh_run "sudo apt-get install -y -qq nginx"
    ssh_run "sudo systemctl enable --now nginx"

    # ── PostgreSQL ─────────────────────────────────────────────────────────────
    ssh_run "sudo apt-get install -y -qq postgresql postgresql-contrib"
    ssh_run "sudo systemctl enable --now postgresql"
    ssh_run "sudo -u postgres psql -c \"CREATE USER gamba WITH PASSWORD 'gamba';\" 2>/dev/null || true"
    ssh_run "sudo -u postgres psql -c \"CREATE DATABASE gamba OWNER gamba;\" 2>/dev/null || true"
    # Allow connections from the internal subnet (backends connect via internal IP)
    ssh_run "echo \"host all gamba 10.0.1.0/24 md5\" | sudo tee -a /etc/postgresql/15/main/pg_hba.conf"
    ssh_run "echo \"listen_addresses = '*'\" | sudo tee -a /etc/postgresql/15/main/postgresql.conf"
    ssh_run "sudo systemctl restart postgresql"

    # ── Redis ──────────────────────────────────────────────────────────────────
    ssh_run "sudo apt-get install -y -qq redis-server"
    # Bind to all interfaces — firewall restricts port 6379 to internal subnet only
    ssh_run "sudo sed -i 's/^bind 127.0.0.1.*/bind 0.0.0.0/' /etc/redis/redis.conf"
    ssh_run "sudo sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf"
    ssh_run "sudo systemctl enable --now redis-server"
    ssh_run "sudo systemctl restart redis-server"

    echo "==> Infra VM ready (Nginx + PostgreSQL + Redis)"
    ;;

  backend)
    ssh_run "sudo apt-get install -y -qq python3 python3-pip python3-venv"
    ssh_run "mkdir -p /home/gamba/gamba"
    echo "==> Backend VM ready"
    ;;

  *)
    echo "Unknown role: ${ROLE}. Must be infra | backend"
    exit 1
    ;;
esac

echo "==> Done: ${INSTANCE}"
