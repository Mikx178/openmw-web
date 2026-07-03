# SPDX-License-Identifier: GPL-3.0-or-later
# openmw-wasm infrastructure — CI deploy identity (GitHub Actions -> GCP via Workload
# Identity Federation). No long-lived JSON keys; GitHub's OIDC token is exchanged for
# short-lived GCP credentials, scoped to this one repo.

resource "google_service_account" "deployer" {
  account_id   = "openmw-deployer"
  display_name = "GitHub Actions deployer (openmw-wasm)"
}

# Just enough to scp/ssh into the VM through IAP and no more.
locals {
  deployer_roles = [
    "roles/compute.viewer",             # look up the instance
    "roles/iap.tunnelResourceAccessor", # tunnel SSH through IAP
    "roles/compute.osAdminLogin",       # OS Login with sudo (to write /var/www + reload nginx)
  ]
}

resource "google_project_iam_member" "deployer" {
  for_each = toset(local.deployer_roles)
  project  = var.gcp_project
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  # Only tokens from your repo are accepted.
  attribute_condition = "assertion.repository == \"${var.github_repo}\""
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Let workflows from the repo impersonate the deployer SA.
resource "google_service_account_iam_member" "wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
