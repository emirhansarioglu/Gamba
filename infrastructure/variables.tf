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
  description = "Number of backend FastAPI nodes (1, 3, or 5)"
  type        = number
  default     = 1
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for VM access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
