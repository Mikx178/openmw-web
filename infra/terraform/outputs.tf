# SPDX-License-Identifier: GPL-3.0-or-later

output "cloudflare_nameservers" {
  description = "Set THESE as your domain's nameservers at the registrar to activate the zone."
  value       = cloudflare_zone.this.name_servers
}

output "vm_public_ip" {
  description = "The origin IP (locked to Cloudflare by firewall)."
  value       = google_compute_address.web.address
}

output "instance_name" {
  value = google_compute_instance.web.name
}

output "instance_zone" {
  value = var.gcp_zone
}

# Feed these two into the GitHub repo as Actions variables (not secrets — they're not sensitive).
output "wif_provider" {
  description = "GH secret WIF_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  description = "GH secret DEPLOY_SA"
  value       = google_service_account.deployer.email
}
