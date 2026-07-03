# SPDX-License-Identifier: GPL-3.0-or-later
# openmw-wasm infrastructure — input variables.

variable "gcp_project" {
  type        = string
  description = "GCP project ID."
}

# Always-free e2-micro is only free in us-west1, us-central1, us-east1.
variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-micro" # always-free tier
}

variable "boot_image" {
  type    = string
  default = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "boot_disk_gb" {
  type    = number
  default = 30 # always-free allows up to 30GB standard PD
}

# --- Cloudflare ---
variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token with Zone:Edit, DNS:Edit, Zone Settings:Edit, Cache Rules:Edit, and Zone:Create on the account."
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID (Dashboard -> any domain -> Overview -> API panel)."
}

# The sites this box serves. `openmw` is the static WASM app; `app` is the dynamic
# second site (nginx reverse-proxies it to a local port). Add more as needed.
variable "domains" {
  type = object({
    openmw = string # e.g. "play.example.com"
    app    = string # e.g. "app.example.com"  (the dynamic site)
  })
}

# The zone (registrable domain) that Cloudflare will manage, e.g. "example.com".
variable "cloudflare_zone" {
  type = string
}

# --- CI (GitHub Actions via Workload Identity Federation) ---
variable "github_repo" {
  type        = string
  description = "owner/repo allowed to deploy, e.g. \"you/openmw-wasm\"."
}
