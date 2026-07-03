# SPDX-License-Identifier: GPL-3.0-or-later
# openmw-wasm infrastructure — Cloudflare zone, DNS, cache rules, and COEP-safe settings.

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Terraform creates the zone; set the outputted nameservers at your registrar to activate it.
resource "cloudflare_zone" "this" {
  account_id = var.cloudflare_account_id
  zone       = var.cloudflare_zone
  plan       = "free"
}

# Zone settings. The CRITICAL bits are rocket_loader + email_obfuscation OFF: both inject
# cross-origin scripts, which "Cross-Origin-Embedder-Policy: require-corp" blocks -> the
# game page would fail to boot. Brotli on; edge compresses what the origin sends raw.
resource "cloudflare_zone_settings_override" "this" {
  zone_id = cloudflare_zone.this.id
  settings {
    rocket_loader     = "off"
    email_obfuscation = "off"
    brotli            = "on"
    ssl               = "full" # origin uses a self-signed cert; edge<->origin still encrypted
    always_use_https  = "on"
    min_tls_version   = "1.2"
    http3             = "on"
  }
}

locals {
  a_records = {
    openmw = split(".", var.domains.openmw)[0] == var.cloudflare_zone ? "@" : replace(var.domains.openmw, ".${var.cloudflare_zone}", "")
    app    = replace(var.domains.app, ".${var.cloudflare_zone}", "")
  }
}

# Proxied A records (orange cloud) -> the VM. Proxying is what gives free CDN + TLS + hides IP.
resource "cloudflare_record" "openmw" {
  zone_id = cloudflare_zone.this.id
  name    = local.a_records.openmw
  type    = "A"
  content = google_compute_address.web.address
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "app" {
  zone_id = cloudflare_zone.this.id
  name    = local.a_records.app
  type    = "A"
  content = google_compute_address.web.address
  proxied = true
  ttl     = 1
}

# Cache rule: the wasm/data/js aren't cached by default (unknown extensions). Force them
# eligible and hold them at the edge for a year so origin fetches (free-tier egress) are rare.
# Content is versioned by rebuild; purge the cache (or rename) when you redeploy the engine.
resource "cloudflare_ruleset" "cache" {
  zone_id = cloudflare_zone.this.id
  name    = "openmw static cache"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules {
    ref         = "cache_engine_assets"
    description = "Cache openmw wasm/data/js/assets long at the edge"
    expression  = "(http.host eq \"${var.domains.openmw}\" and http.request.uri.path.extension in {\"wasm\" \"data\" \"js\" \"br\" \"html\" \"css\"})"
    action      = "set_cache_settings"
    action_parameters {
      cache = true
      edge_ttl {
        mode    = "override_origin"
        default = 31536000 # 1 year
      }
      browser_ttl {
        mode    = "override_origin"
        default = 86400 # 1 day (index.html re-checks daily)
      }
    }
  }
}
