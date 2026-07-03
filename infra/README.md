<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Infrastructure (openmw-wasm + a second site, ~free)

Serve the static openmw-wasm site (and a second dynamic site) from one **GCP
always-free `e2-micro`** VM behind a **free Cloudflare** zone. Cloudflare's
unmetered edge bandwidth serves the heavy `.wasm`/`.data`, so GCP's 1 GB/month
free egress is only touched on rare cache fills. Net cost: about $0.

```
visitors ─HTTPS─▶ Cloudflare (free CDN, edge TLS, caches wasm/data)
                       │ origin pulls only on cache-miss
                       ▼
        GCP e2-micro VM · nginx
          play.example.com  → /var/www/openmw-wasm/play   (static, COOP/COEP)
          app.example.com   → 127.0.0.1:3000              (your dynamic app)
```

## Why it's built this way (the non-obvious constraints)

- **COOP/COEP are mandatory.** openmw-wasm needs SharedArrayBuffer, which requires
  `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy:
  require-corp` on every response, over HTTPS. nginx sets them
  (`nginx/openmw-wasm.conf`).
- **Cloudflare must not inject cross-origin scripts.** Rocket Loader and Email
  Obfuscation add cross-origin `<script>`s that `require-corp` blocks — the
  Terraform turns both **off**.
- **`.wasm`/`.data` aren't cached by default.** A Cloudflare cache rule forces them
  cacheable with a 1-year edge TTL, so origin egress stays tiny.
- **Origin is locked to Cloudflare.** The firewall allows 80/443 only from
  Cloudflare's IP ranges; SSH only via Google IAP. No public SSH, no bypassing the CDN.
- **1 GB RAM is tight.** cloud-init adds a 2 GB swapfile so nginx + a backend + apt
  don't OOM.

## One-time setup

### 0. Prerequisites
- A registered domain (you'll point its nameservers at Cloudflare).
- `gcloud` + `terraform` installed; a GCP project with billing enabled (the VM
  stays in the always-free tier, but a billing account must exist).
- A Cloudflare account + an API token (My Profile → API Tokens) with
  **Zone:Edit, DNS:Edit, Zone Settings:Edit, Cache Rules:Edit** and account-level
  **Zone:Create**.

### 1. Provision
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # fill in project, domains, CF token, repo
terraform init
terraform apply
```
Then **point your registrar's nameservers** at the two values in the
`cloudflare_nameservers` output. Cloudflare emails you when the zone goes active
(minutes to a couple hours).

### 2. Wire up CI
`terraform output` prints `wif_provider` and `deployer_service_account`. Add them
to the GitHub repo:
- Settings → Secrets and variables → Actions → **New secret**
  - `WIF_PROVIDER` = the `wif_provider` output
  - `DEPLOY_SA`    = the `deployer_service_account` output

No SSH keys or JSON key files — GitHub's OIDC token is exchanged for short-lived
GCP credentials scoped to this repo only.

### 3. Edit the vhost domains
In `infra/nginx/openmw-wasm.conf` set `server_name` to your openmw domain. For the
second site, copy `infra/nginx/app.conf.example` → `infra/nginx/app.conf`, set its
`server_name` and upstream port, and add it to the deploy step (or ship it once by
hand). Do **not** put COEP headers on the app vhost unless it also needs them.

## Deploying openmw-wasm

The engine binaries are gitignored, so publish them to a GitHub Release after a
local build, then run the workflow:

```bash
./wasm-build/link-openmw.sh && ./wasm-build/make_br.sh
cp build-wasm/openmw.{js,wasm,data} play/
gh release create build-$(date +%Y%m%d) \
  play/openmw.js play/openmw.wasm play/openmw.data \
  play/openmw.js.br play/openmw.wasm.br play/openmw.data.br
```
Then run the **deploy-openmw** workflow (Actions tab → Run workflow). It pulls the
release artifacts, ships them + the vhost to the VM through IAP, and reloads nginx.

**After each engine redeploy, purge the Cloudflare cache** (or use versioned
filenames) so visitors get the new `.wasm`/`.data` rather than the year-cached old
ones.

## Deploying the second (dynamic) site

That app is its own project. Run it on the VM as a `systemd` service or container
listening on `127.0.0.1:3000` (match `app.conf`), and give it its own deploy
workflow. Watch RAM on the `e2-micro`: keep the backend lean (SQLite over a heavy
DB, modest worker counts); the swapfile is a safety net, not headroom.

## Files

| Path | Purpose |
|------|---------|
| `terraform/main.tf` | VM, static IP, firewall (Cloudflare-only + IAP SSH) |
| `terraform/cloudflare.tf` | Zone, proxied DNS, cache rule, COEP-safe zone settings |
| `terraform/ci.tf` | Deploy service account + Workload Identity Federation for GitHub |
| `cloud-init/startup.tftpl` | Base box: swap, nginx, self-signed origin cert, real-IP |
| `nginx/openmw-wasm.conf` | Static vhost with COOP/COEP + long cache |
| `nginx/app.conf.example` | Template reverse-proxy vhost for the dynamic site |
| `../.github/workflows/deploy-openmw.yml` | Release-artifact → IAP deploy |

## Hardening later (optional)
- Cloudflare **Origin CA cert** + SSL mode **Full (strict)** instead of the
  self-signed cert + Full.
- Cloudflare **Tiered Cache** (free) to further cut origin fills.
- Cloudflare **WAF / Bot Fight Mode** (careful: challenge pages inject scripts;
  exclude the openmw host if COEP complains).
- A remote **Terraform state backend** (GCS bucket) instead of local state.
