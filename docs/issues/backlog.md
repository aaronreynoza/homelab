# Deferred Work Backlog

Tasks identified during cluster setup that are not needed for the initial deployment but should be addressed for production readiness.

## Priority 1: Ops Maturity (Next Sprint)

### ~~Templatize environment-specific values~~ → RESOLVED (2026-03-17)
- **Resolved:** Fixed Cilium `k8sServiceHost` (was broken by history rewrite). ArgoCD now sources app manifests from Forgejo prod repo `apps/` directory with env-specific values.

### ~~Store Newt credentials in AWS Secrets Manager~~ → DONE (SOPS + age)
- **Resolved:** Migrated to SOPS + age encryption (ADR-004). All secrets in `environments/prod/secrets/` encrypted at rest. AWS SM dependency removed. Proxmox creds also migrated.

### Automate worker reboot for disk partitioning
- **Why:** `machine.disks` only applies on reboot. Current flow may need manual reboot.
- **Fix:** Add `null_resource` with `talosctl reboot` + readiness poll after config apply
- **Alternative:** Investigate if Talos auto-reboots on disk config change in `auto` apply mode

### Pre-commit hooks
- **Why:** No linting or validation before commits
- **Fix:** Add `terraform fmt`, `terraform validate`, YAML lint, Helm lint
- **Effort:** Half day

## Priority 2: Production Hardening

### ~~TrueNAS VM for NFS storage~~ → PERMANENTLY DEFERRED
- **Decision:** TrueNAS not worth it for 2 disks. Storage: ZFS on Proxmox + Longhorn + NFS from Proxmox.
- See "Won't Do" section below.

### ~~ctrld on OPNSense for DNS management~~ → SUPERSEDED
- **Resolved:** Split-horizon DNS implemented via OPNSense Unbound wildcard override + CoreDNS custom zone (2026-03-17). ctrld approach was bypassed — native DNS works better for our setup.
- Internal: `*.aaron.reynoza.org` → 10.10.10.228 (Cilium Gateway)
- External: `*.aaron.reynoza.org` → Pangolin VPS (Cloudflare DNS)

### OPNSense API automation
- **Why:** Firewall rules are currently manual via Web UI
- **Fix:** OPNSense has a REST API at `/api/`. Could use Terraform `http` provider or community `browningluke/opnsense` provider
- **Why deferred:** OPNSense is already configured correctly, rules rarely change

### ~~Velero + Longhorn backups~~ → DEPLOYED
- **Resolved:** Velero deployed via ArgoCD. Target is Backblaze B2 (S3-compatible), not AWS S3.
- **Remaining:** Configure scheduled backups, test full restore procedure.
- **Issue:** `docs/issues/005-velero-cluster-backup.md`

### CARP HA for OPNSense
- **Issue:** `docs/issues/001-opnsense-ha-carp-failover.md`
- **Why deferred:** Requires second OPNSense VM, adds complexity

### Longhorn replica increase
- **Issue:** `docs/issues/003-longhorn-cross-node-replicas.md`
- **Current:** replica: 1 (single-node storage, data loss risk)
- **Fix:** Increase to 2 when 3+ workers with data disks

## Priority 3: Dev Environment

### Deploy dev cluster on VLAN 11
- **Why:** Need isolated testing environment
- **Blocks:** Templatized manifests (Priority 1)
- **Steps:** New `environments/dev/` directory, different IPs, same modules
- **Network:** 10.11.10.0/16, VLAN 11, gateway 10.11.10.1

### ~~Harbor container registry per environment~~ → DEPLOYED
- **Resolved:** Harbor deployed via ArgoCD (2026-03-12). Pull-through cache configured for GHCR, Docker Hub, k8s.io (2026-03-19). Talos containerd mirrors route through Harbor.

## Priority 4: Applications

### Race telemetry app (ApexDirector)
- **Why:** Production workload with paying clients
- **Status:** Traffic path fully validated via Pangolin + Cilium Gateway
- **Steps:** ArgoCD Application manifest, Pangolin resource, domain config

### Media services (Jellyfin, etc.)
- **Why:** Personal use
- **Why deferred:** Not urgent, deploy after telemetry app

## Won't Do (Decided Against)

### Ansible for Talos operations
- **Why not:** Talos is immutable and API-driven. No SSH, no shell. `talosctl` and Terraform provider handle everything. Adding Ansible creates unnecessary tool sprawl.
- **Reference:** PM analysis from 2026-03-11 expert review

### Cloudflare Tunnel
- **Why not:** See ADR-003. Conflicts with learning goals and traffic ownership.

### TrueNAS
- **Why not:** Only 2 HDDs available — not worth the overhead of a dedicated TrueNAS VM. ZFS pool managed directly on Proxmox (hdd-mirror), NFS exported to K8s for media.

---

### MkDocs documentation site → CANCELLED
- **Replaced by:** Outline wiki (HOMELAB-72). MkDocs tickets cancelled (HOMELAB-17, 46, 47).

### Coder workspace platform → REPLACED
- **Replaced by:** code-server + Claude Code Remote Control on Management VM 110 (2026-03-19)
- **Cleanup:** HOMELAB-68 (remove Coder) is in Todo state

---

**Last Updated:** 2026-03-19
