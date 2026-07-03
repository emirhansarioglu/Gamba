terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_project_service" "required_apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "gamba" {
  location      = var.region
  repository_id = var.artifact_repo_id
  description   = "Docker images for Gamba"
  format        = "DOCKER"

  depends_on = [google_project_service.required_apis]
}

resource "google_service_account" "gamba_vm" {
  account_id   = "gamba-vm-sa"
  display_name = "Gamba VM Service Account"

  depends_on = [google_project_service.required_apis]
}

resource "google_project_iam_member" "vm_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gamba_vm.email}"
}

resource "google_compute_network" "gamba" {
  name                    = "gamba-network"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "gamba" {
  name          = "gamba-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.gamba.id
}

resource "google_compute_address" "infra_public" {
  name = "gamba-infra-public-ip"
}

resource "google_compute_address" "infra_internal" {
  name         = "gamba-infra-internal-ip"
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.gamba.id
  region       = var.region
}

resource "google_compute_firewall" "allow_http" {
  name    = "gamba-allow-http"
  network = google_compute_network.gamba.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nginx-lb"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "gamba-allow-ssh"
  network = google_compute_network.gamba.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gamba-vm"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "gamba-allow-internal"
  network = google_compute_network.gamba.name

  allow {
    protocol = "tcp"
    ports    = ["8000", "5432", "6379"]
  }

  source_ranges = ["10.0.1.0/24"]
  target_tags   = ["gamba-vm"]
}

resource "google_compute_instance" "backend" {
  count        = var.backend_node_count
  name         = "backend-${count.index + 1}"
  machine_type = var.machine_type
  tags         = ["gamba-vm"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gamba.id

    access_config {}
  }

  service_account {
    email  = google_service_account.gamba_vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    ssh-keys = "gamba:${file(var.ssh_public_key_path)}"
  }

  metadata_startup_script = replace(templatefile("${path.module}/startup-backend.sh.tpl", {
    artifact_registry_host = local.artifact_registry_host
    backend_image          = local.backend_image
    database_url           = "postgresql://gamba:gamba@${google_compute_address.infra_internal.address}:5432/gamba"
    redis_url              = "redis://${google_compute_address.infra_internal.address}:6379/0"
    allowed_origins        = "http://${google_compute_address.infra_public.address}"
    jwt_secret_key         = var.jwt_secret_key
  }), "\r\n", "\n")

  depends_on = [
    google_artifact_registry_repository.gamba,
    google_project_iam_member.vm_artifact_reader,
  ]
}

resource "google_compute_instance" "infra" {
  name         = "infra"
  machine_type = var.machine_type
  tags         = ["nginx-lb", "gamba-vm"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gamba.id
    network_ip = google_compute_address.infra_internal.address

    access_config {
      nat_ip = google_compute_address.infra_public.address
    }
  }

  service_account {
    email  = google_service_account.gamba_vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    ssh-keys = "gamba:${file(var.ssh_public_key_path)}"
  }

  metadata_startup_script = replace(templatefile("${path.module}/startup-infra.sh.tpl", {
    artifact_registry_host = local.artifact_registry_host
    frontend_image         = local.frontend_image
    nginx_image            = local.nginx_image
    postgres_image         = local.postgres_image
    redis_image            = local.redis_image
    backend_ips            = [for b in google_compute_instance.backend : b.network_interface[0].network_ip]
  }), "\r\n", "\n")

  depends_on = [
    google_artifact_registry_repository.gamba,
    google_project_iam_member.vm_artifact_reader,
  ]
}

resource "local_file" "nginx_conf" {
  content = templatefile("${path.module}/nginx.conf.tpl", {
    backend_ips = [for b in google_compute_instance.backend : b.network_interface[0].network_ip]
  })
  filename = "${path.module}/nginx.conf"
}
