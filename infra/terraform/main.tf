# SPDX-License-Identifier: GPL-3.0-or-later
# openmw-wasm infrastructure — GCP always-free VM + firewall.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google     = { source = "hashicorp/google", version = "~> 5.0" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.40" }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# Static external IP. Always-free includes one in-use regional IP in the free regions.
resource "google_compute_address" "web" {
  name   = "openmw-web-ip"
  region = var.gcp_region
}

# The always-free VM. cloud-init installs nginx, a swapfile (1GB RAM is tight), a
# self-signed origin cert, and the Cloudflare real-IP config. Site vhosts + content
# are delivered afterward by CI (see .github/workflows/deploy-openmw.yml).
resource "google_compute_instance" "web" {
  name         = "openmw-web"
  machine_type = var.machine_type
  zone         = var.gcp_zone
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_gb
      type  = "pd-standard" # standard PD is the free-tier disk
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.web.address
    }
  }

  metadata = {
    # OS Login lets CI authenticate via IAM/WIF instead of managed SSH keys.
    enable-oslogin = "TRUE"
    user-data = templatefile("${path.module}/../cloud-init/startup.tftpl", {
      openmw_domain = var.domains.openmw
      app_domain    = var.domains.app
    })
  }

  # A cheap box is disposable; let Terraform recreate it without capacity errors.
  scheduling {
    automatic_restart = true
    preemptible       = false
  }
}

# Cloudflare's published edge IPs — used to lock the origin so only Cloudflare can reach it.
data "cloudflare_ip_ranges" "cf" {}

# 80/443 reachable ONLY from Cloudflare. Direct-to-origin hits are dropped, which both
# saves free-tier egress and stops anyone from bypassing the CDN (and the CO isolation).
resource "google_compute_firewall" "from_cloudflare" {
  name          = "allow-web-from-cloudflare"
  network       = "default"
  target_tags   = ["web"]
  source_ranges = concat(data.cloudflare_ip_ranges.cf.ipv4_cidr_blocks, data.cloudflare_ip_ranges.cf.ipv6_cidr_blocks)
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# SSH only via Google IAP (35.235.240.0/20). No public 22. CI and admins tunnel through IAP.
resource "google_compute_firewall" "ssh_iap" {
  name          = "allow-ssh-iap"
  network       = "default"
  target_tags   = ["web"]
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
