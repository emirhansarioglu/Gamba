locals {
  ssh_public_key_content = try(
    file(pathexpand(var.ssh_public_key_path)),
    fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ? file(pathexpand("~/.ssh/id_ed25519.pub")) :
    fileexists(pathexpand("~/.ssh/id_rsa.pub")) ? file(pathexpand("~/.ssh/id_rsa.pub")) :
    file(pathexpand(var.ssh_public_key_path))
  )
  artifact_registry_host = "${var.region}-docker.pkg.dev"
  artifact_registry_repo = "${local.artifact_registry_host}/${var.project_id}/${var.artifact_repo_id}"

  backend_image    = "${local.artifact_registry_repo}/gamba-backend:${var.image_tag}"
  frontend_image   = "${local.artifact_registry_repo}/gamba-frontend-assets:${var.image_tag}"
  nginx_image      = var.nginx_image
  postgres_image   = var.postgres_image
  redis_image      = var.redis_image
  prometheus_image = var.prometheus_image
  grafana_image    = var.grafana_image
}
