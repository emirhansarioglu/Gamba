output "lb_ip" {
  description = "Public IP of the infra VM (Nginx load balancer)"
  value       = google_compute_address.infra_public.address
}

output "backend_ips" {
  description = "Internal IPs of backend nodes"
  value       = [for b in google_compute_instance.backend : b.network_interface[0].network_ip]
}


output "infra_ip" {
  description = "Internal IP of the infra VM (PostgreSQL + Redis)"
  value       = google_compute_address.infra_internal.address
}

output "backend_image" {
  value = local.backend_image
}

output "frontend_image" {
  value = local.frontend_image
}

output "nginx_image" {
  value = local.nginx_image
}

output "postgres_image" {
  value = local.postgres_image
}

output "redis_image" {
  value = local.redis_image
}

output "prometheus_url" {
  description = "Prometheus URL when observability is enabled"
  value       = var.enable_observability ? "http://${google_compute_address.infra_public.address}:9090" : null
}

output "grafana_url" {
  description = "Grafana URL when observability is enabled"
  value       = var.enable_observability ? "http://${google_compute_address.infra_public.address}:3000" : null
}

output "artifact_registry_host" {
  value = local.artifact_registry_host
}
