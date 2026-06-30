output "lb_ip" {
  description = "Public IP of the infra VM (Nginx load balancer)"
  value       = google_compute_instance.infra.network_interface[0].access_config[0].nat_ip
}

output "infra_ip" {
  description = "Internal IP of the infra VM (PostgreSQL + Redis)"
  value       = google_compute_instance.infra.network_interface[0].network_ip
}

output "backend_ips" {
  description = "Internal IPs of backend nodes"
  value       = [for b in google_compute_instance.backend : b.network_interface[0].network_ip]
}
