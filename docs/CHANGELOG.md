# Changelog

This document tracks significant milestones, work sessions, and progress on the homelab project.

---

## 2026-03-19 — Agent Pipeline & Workspace

- **Agent workspace on VM 110**: code-server v4.111.0 + Claude Code v2.1.79 Remote Control on Management VM 110
  - Dedicated `claude-agent` user with cgroup limits (4 CPU, 8GB RAM)
  - Workspace at `~/workspace/` with project-scoped layout
  - code.aaron.reynoza.org via Caddy + Cilium Gateway + Pangolin
  - 9 skills deployed (researcher, planner, reviewer, executor, verifier, tracker, technical-writer, orchestrator-common, plane-workflow)
  - Plane MCP connected for ticket management
- **SP1 (Agent Config)**: Private `agent-config` Forgejo repo with CLAUDE.md, skills, MCP config, QA checks
- **SP2 (Skill Framework)**: 7 specialized skills verified end-to-end from Remote Control
- **SP3 (Orchestration Pipeline)**: Project-scoped orchestrator with dual-mode (work session/normal), backtracking, dangerous ops handling
- **Harbor pull-through cache**: Proxy cache projects for GHCR, Docker Hub, k8s.io with Talos containerd mirrors

## 2026-03-18 — Plane & Agent Foundation

- **Plane deployed**: Project management at plane.aaron.reynoza.org with 73 tickets, 7 modules, 12 labels
- **Plane MCP**: MCP server for Claude Code to read/write Plane tickets
- **Plane workflow guide**: Documented ticket lifecycle and conventions

## 2026-03-17 — Subdomains, LLM Stack, DNS

- **Cilium Gateway API**: Single gateway at 10.10.10.228 with HTTPRoutes per service (replaced per-service LoadBalancer IPs)
- **Split-horizon DNS**: OPNSense wildcard override + CoreDNS custom zone for internal resolution
- **Pangolin IaC**: `pangolin-resources.py` script + `resources.yaml` for declarative public resource management
- **All services on subdomains**: forgejo/harbor/argocd/grafana/zitadel/plane/chat at *.aaron.reynoza.org
- **LLM stack**: Ollama + LiteLLM + Open WebUI at chat.aaron.reynoza.org
- **GPU passthrough**: NVIDIA RTX 3060 via VFIO to K8s worker, verified with Ollama
- **GitHub push mirrors**: Forgejo → GitHub sync_on_commit for infra-core and prod repos
- **CI/CD pipelines**: 4 workflow files, mgmt VM runner (Terraform) + K8s runner (lint/build)

## 2026-03-16 — Forgejo Migration & Repo Split

- **Two-repo architecture**: infra-core (public OSS) + prod (private env-specific)
- **Forgejo source of truth**: Migrated from GitHub, history purged of secrets
- **Repo rename**: homelab → infra-core, homelab-env → prod
- **DNS fix**: k8sServiceHost broken by history rewrite, fixed

## 2026-03-14 — SSO & Management VM

- **Zitadel SSO**: Terraform-driven OIDC for ArgoCD, Forgejo, Grafana, Harbor
- **Management VM (ID 110)**: Debian 12, dual-homed, Ansible-configured, Forgejo runner

## 2026-03-12 — Platform Apps & Storage

- **All platform apps deployed**: Forgejo, Harbor, Zitadel, Velero, kube-prometheus-stack, Loki, Tempo, Mimir, OTel Collector
- **SOPS secrets management**: Age encryption for all K8s secrets
- **Cilium LB-IPAM**: IP pool 10.10.10.220-250
- **Storage decision**: Longhorn on SSD for PVCs, NFS from Proxmox for media, TrueNAS deferred
- **Worker kubelet fix**: Removed NVIDIA extensions from non-GPU workers

## 2026-03-10 — Talos Cluster

- **Talos Linux v1.12.5**: 1 CP + 2 workers on VLAN 10
- **Cilium CNI**: With Hubble observability
- **Longhorn storage**: Replica 1 on SSD
- **ArgoCD**: App-of-apps pattern, sourcing from Forgejo

---

## 2026-02-04 - Phase 2 Network Infrastructure Complete

### Summary
- **VLAN connectivity fully working** with firewall enabled
- Recovered from config.xml corruption that wiped all VLAN settings
- SSH/HTTPS access to OPNSense working through firewall
- VLAN 10 (PROD) tested: DHCP, gateway, and NAT all functional

### Details
- **Config Recovery**:
  - Direct `sed` edit to config.xml corrupted OPNSense config
  - Reboot caused full reset, losing all VLAN configuration
  - Lesson learned: NEVER edit config.xml directly, always use Web UI
  - Recreated VLANs, DHCP, and firewall rules from scratch

- **Firewall Fixes**:
  - Disabled "Block private networks" on WAN (required since WAN is on private subnet)
  - Added WAN rule to allow SSH/HTTPS to self
  - Firewall now works correctly with all access methods

- **VLAN Configuration** (recreated):
  - PROD (VLAN 10): 10.10.10.1/16, DHCP REDACTED_VLAN_IP0-200
  - DEV (VLAN 11): 10.11.10.1/16, DHCP 10.11.10.50-200
  - Parent interface: LAN trunk NIC

- **Test Results** (VLAN 10):
  - Container got DHCP from VLAN 10 gateway
  - Gateway ping: 10.10.10.1 ✓
  - Internet ping: 8.8.8.8 ✓ (NAT working)

### Outcomes
- Phase 2 Network Infrastructure is COMPLETE
- Backup saved to OPNSense `/conf/backup/`
- Ready for Phase 3 (Multi-Environment Clusters)

### Lessons Learned
1. Never edit config.xml directly - use Web UI only
2. Always backup after changes
3. "Block private networks" must be off when WAN is on private subnet
4. Interface mappings can swap on reboot - verify via MAC addresses

---

## 2026-02-01 - WAN/LAN Split, VLAN Debugging, Storage Proposal

### Summary
- Completed WAN/LAN bridge split on primary host (vmbr0 LAN, vmbr1 WAN)
- Debugged VLAN/OPNSense interface mapping issues
- Compared infrastructure with William's homelab approach
- Created VLAN fix runbook and TrueNAS storage proposal

### Details
- **Network Changes**:
  - Split bond on primary host: dedicated NIC for LAN trunk, separate NIC for WAN
  - Updated Terraform `wan_bridge` variable
  - Applied changes to OPNSense VM NICs
- **VLAN Debugging**:
  - Discovered interface mapping issues after config restores
  - Root cause: OPNSense vtnet assignments change based on config, causing NAT/routing issues
  - Created MAC-matching runbook for reliable interface identification
- **Infrastructure Comparison**:
  - Reviewed William's `infra-clean` repo (Flux, SOPS, Packer, strong ops docs)
  - Identified items to adopt: pre-commit hooks, SOPs, checklists, guardrails
  - Keeping our architecture: ArgoCD, AWS Secrets Manager + ESO, core/environments split
- **Storage Decision**:
  - Proposed TrueNAS VM for media storage (NFS to Kubernetes)
  - Longhorn remains for app configs/databases
  - Enables phone uploads to media library via TrueNAS app

### Outcomes
- WAN/LAN split complete (needs VLAN verification)
- Created `docs/runbooks/vlan-opnsense-fix.md` for future sessions
- Created `docs/decisions/002-truenas-storage.md` with storage proposal
- Task list created for ops maturity improvements

---

## 2026-01-22 - OPNSense Install, VLAN Setup, and WAN/LAN Split Plan

### Summary
- Deployed OPNSense VM via Terraform and completed the install wizard
- Configured VLAN 10/11 interfaces, DHCP, and firewall rules for isolation
- Validated VLAN 10 with a tagged test VM (VM 200) and discovered outbound NAT failure

### Details
- **OPNSense**:
  - VLAN 10 (PROD) at `10.10.10.1/16`, VLAN 11 (DEV) at `10.11.10.1/16`
  - DHCP enabled (PROD pool observed at `REDACTED_VLAN_IP0-10.10.10.200`)
  - Rules: block PROD <-> DEV, allow each VLAN to any
  - WAN on DHCP behind private subnet (Block private/bogon disabled)
- **Proxmox**:
  - `vmbr0` VLAN-aware with `bridge-vids 10 11` on both Proxmox hosts
  - Test VM on VLAN 10 receives DHCP but cannot reach the internet
- **Root Cause**:
  - WAN and LAN are on the same L2 (both on `vmbr0`), so NAT does not translate correctly

### Outcomes
- VLANs and DHCP are functional; inter-VLAN isolation rules are in place
- Next step is to split WAN to a dedicated NIC/bridge (`vmbr1`) on primary host

## 2026-01-21 - Terraform Backend Setup & State Migration

### Summary
- Created S3 + DynamoDB backend for Terraform remote state
- Migrated bootstrap state from local to S3 (critical fix)
- Documented backend setup process to prevent single points of failure

### Details
- **AWS Resources Created**:
  - S3 bucket for Terraform state (versioned, encrypted)
  - DynamoDB table for state locking
- **State Migration**:
  - Bootstrap initially used local state (chicken-and-egg problem)
  - Immediately migrated to S3 after backend resources created
  - Local state files removed to avoid confusion
- **Documentation**:
  - Created `docs/runbooks/terraform-backend-setup.md`
  - Documents why remote state is critical (no single points of failure)
  - Includes disaster recovery procedures

### Outcomes
- All terraform state now in S3 - survives local machine loss
- State locking prevents concurrent modification issues
- Clear runbook for future reference

---

## 2026-01-21 - OPNSense Terraform Module & Documentation Refactor

### Summary
- Created OPNSense Terraform module for firewall/router VM
- Refactored CLAUDE.md from 845 lines to 130 lines
- Moved detailed content to dedicated documentation files

### Details
- **OPNSense Module** (`core/terraform/modules/opnsense/`):
  - Downloads OPNSense ISO automatically
  - Creates VM with 2 NICs (WAN + LAN trunk)
  - Configures UEFI boot with CD-ROM for initial installation
- **Repository Structure**:
  - Code in `core/terraform/` (modules, bootstrap, live configs)
  - Values only in `environments/` (terraform.tfvars files)
- **Documentation Refactor**:
  - Created `docs/architecture.md` (network diagrams)
  - Created `docs/roadmap.md` (implementation phases)
  - Slimmed CLAUDE.md to essential context only

### Outcomes
- Ready to deploy OPNSense VM
- Clean separation: code in core, config in environments
- Documentation is organized and maintainable

---

## 2026-01-21 - Proxmox Recovery & Documentation Setup

### Summary
- Recovered Proxmox host from emergency mode (stale fstab + network misconfig)
- Established documentation structure for ongoing work

### Details
- **Incident**: Proxmox booted into systemd emergency mode
- **Root causes**: Stale `/etc/fstab` mount + wrong NIC names in `/etc/network/interfaces`
- **Resolution**: See [runbooks/proxmox-recovery.md](runbooks/proxmox-recovery.md)

### Outcomes
- Proxmox UI accessible
- Bond0 active-backup with primary NIC
- ZFS pool `hdd-pool` mounted at `/mnt/hd`

---

## 2026-01-XX - Repository Restructure (Phase 1)

### Summary
- Transformed repository into modular core/environments structure
- Created reusable Terraform modules
- Organized Helm charts by layer (platform/apps)

### Details
- Created `core/terraform/modules/` with talos-cluster, proxmox-vm, aws-backend
- Organized charts into `core/charts/platform/` and `core/charts/apps/`
- Set up `environments/prod/` and `environments/dev/` structures
- Fixed several bugs in original ChatGPT-generated code

### Outcomes
- Repository ready for multi-environment deployments
- PR opened: `refactor/modular-structure` branch

---

## Template for Future Entries

```markdown
## YYYY-MM-DD - Title

### Summary
- Brief bullet points of what was accomplished

### Details
- More detailed explanation if needed
- Reference to related docs/runbooks/decisions

### Outcomes
- What's the end state after this work
```
