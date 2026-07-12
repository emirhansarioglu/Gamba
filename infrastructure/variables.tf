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

variable "load_shedding_enabled" {
  description = "Whether backend request load shedding is enabled."
  type        = bool
  default     = true
}

variable "in_flight_soft_limit" {
  description = "Per-backend in-flight request count where probabilistic shedding starts."
  type        = number
  default     = 80
}

variable "in_flight_hard_limit" {
  description = "Per-backend in-flight request count where shedding reaches full pressure before max_shed_probability capping."
  type        = number
  default     = 100
}

variable "max_avg_latency_ms" {
  description = "Latency EWMA threshold in milliseconds before latency-based shedding starts."
  type        = number
  default     = 1500
}

variable "latency_shed_probability" {
  description = "Base latency shedding probability when latency EWMA exceeds max_avg_latency_ms."
  type        = number
  default     = 0.7
}

variable "latency_ewma_alpha" {
  description = "EWMA smoothing factor for observed request latency."
  type        = number
  default     = 0.2
}

variable "max_process_cpu_percent" {
  description = "Per-backend process CPU EWMA threshold before CPU-based shedding starts. 100 means roughly one full core."
  type        = number
  default     = 185
}

variable "cpu_shed_probability" {
  description = "Base CPU shedding probability when process CPU EWMA exceeds max_process_cpu_percent."
  type        = number
  default     = 0.7
}

variable "cpu_ewma_alpha" {
  description = "EWMA smoothing factor for backend process CPU utilization."
  type        = number
  default     = 0.2
}

variable "cpu_sample_interval_seconds" {
  description = "Minimum seconds between backend process CPU samples."
  type        = number
  default     = 1
}

variable "max_shed_probability" {
  description = "Maximum probability cap for probabilistic shedding so the backend can still admit some requests under pressure."
  type        = number
  default     = 1.0
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
