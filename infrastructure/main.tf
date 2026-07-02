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

# ── APIs ───────────────────────────────────────────────────────────────────

resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# ── Network ───────────────────────────────────────────────────────────────────

resource "google_compute_network" "gamba" {
  name                    = "gamba-network"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.required_apis
  ]
}

resource "google_compute_subnetwork" "gamba" {
  name          = "gamba-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.gamba.id
}

# ── Firewall ──────────────────────────────────────────────────────────────────

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

# ── Infra VM (Nginx + PostgreSQL + Redis) ─────────────────────────────────────

resource "google_compute_instance" "infra" {
  name         = "infra"
  machine_type = var.machine_type
  tags         = ["nginx-lb", "gamba-vm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gamba.id
    access_config {}  # public IP — only this VM is internet-facing
  }

  metadata = {
    ssh-keys = "gamba:${file(var.ssh_public_key_path)}"
  }
}

# ── Backend Nodes ─────────────────────────────────────────────────────────────

resource "google_compute_instance" "backend" {
  count        = var.backend_node_count
  name         = "backend-${count.index + 1}"
  machine_type = var.machine_type
  tags         = ["gamba-vm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gamba.id
    access_config {}  # ephemeral public IP for SSH/deploy only; app port 8000 stays firewalled to the internal subnet
  }

  metadata = {
    ssh-keys = "gamba:${file(var.ssh_public_key_path)}"
  }
}

# ── Nginx config (generated from template, used by deploy.sh) ─────────────────

resource "local_file" "nginx_conf" {
  content = templatefile("${path.module}/nginx.conf.tpl", {
    backend_ips = [for b in google_compute_instance.backend : b.network_interface[0].network_ip]
  })
  filename = "${path.module}/nginx.conf"
}
