variable "project_id" {
  description = "GCP project ID"
  type        = string
  # default     = "project-9a0a6f54-8a89-47b8-a40"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west3-a"
}

variable "machine_type" {
  description = "GCP machine type for all VMs"
  type        = string
  default     = "e2-micro"
}

variable "backend_node_count" {
  description = "Number of stateless backend FastAPI nodes. Use 1, 3, or 5 for the assignment runs."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5], var.backend_node_count)
    error_message = "backend_node_count must be one of 1, 3, or 5."
  }
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for VM access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}


variable "artifact_repo_id" {
  description = "Artifact Registry Docker repository name."
  type        = string
  default     = "gamba"
}

variable "image_tag" {
  description = "Docker image tag used for backend and frontend static asset images."
  type        = string
  default     = "dev"
}

variable "nginx_image" {
  description = "Nginx load balancer image pulled by the infra VM."
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "postgres_image" {
  description = "PostgreSQL image pulled by the infra VM."
  type        = string
  default     = "postgres:16"
}

variable "redis_image" {
  description = "Redis image pulled by the infra VM."
  type        = string
  default     = "redis:7"
}

variable "enable_observability" {
  description = "Whether the infra VM should run Prometheus and Grafana containers."
  type        = bool
  default     = true
}

variable "prometheus_image" {
  description = "Prometheus image pulled by the infra VM."
  type        = string
  default     = "prom/prometheus:v2.55.1"
}

variable "grafana_image" {
  description = "Grafana image pulled by the infra VM."
  type        = string
  default     = "grafana/grafana:11.3.0"
}

variable "observability_source_ranges" {
  description = "CIDR ranges allowed to access Grafana and Prometheus. Restrict this for non-demo deployments."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "jwt_secret_key" {
  type      = string
  default   = "gamba-production-secret"
  sensitive = true
}
