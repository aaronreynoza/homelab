# Self-Hosted Media Platform Design

**Goal:** Replace Netflix, Spotify, and Google Photos with a self-hosted media platform running entirely on K8s. Automated content acquisition, hardware-accelerated transcoding, multi-user access with per-user permissions, and off-site backup of irreplaceable personal media.

**Architecture:** NFS-backed storage from Proxmox ZFS for media, Longhorn on SSD for app databases, GPU passthrough for Jellyfin transcoding. All apps in a single `media` namespace, deployed via ArgoCD.

**Tech Stack:** Jellyfin, Navidrome, Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, Gluetun, Jellyseerr, Filebrowser, Recyclarr

---

## Infrastructure Context

| Resource | Value |
|----------|-------|
| Proxmox host | daytona — 56 cores, 128 GB RAM |
| SSD | 240 GB local-lvm (Longhorn, app PVCs) |
| HDD | 2x 4TB WD Gold, ZFS mirror (`hdd-mirror`), ~3.4 TB usable |
| GPU | NVIDIA RTX 3060 (PCIe passthrough to Talos worker) |
| K8s | 1 control plane + 2 workers on Talos Linux v1.12.5 |
| CNI | Cilium with LB-IPAM pool REDACTED_LB_IP–250 |
| Storage | Longhorn (SSD), NFS from Proxmox (HDD) |
| GitOps | ArgoCD (app-of-apps pattern) |
| Public access | Pangolin on Vultr VPS |
| Backup | Velero to AWS S3, rclone to Backblaze B2 |

---

## Storage Architecture

### Design Decision

Hybrid storage model. No TrueNAS VM — not worth the overhead for 2 disks. Bare ZFS + nfs-kernel-server on the Proxmox host directly. See [ADR-002](../decisions/002-truenas-storage.md) for context.

| Layer | Backing | Purpose |
|-------|---------|---------|
| Longhorn (SSD) | local-lvm | App PVCs — databases, configs, platform services |
| NFS (HDD) | hdd-mirror/media-data | Media storage — movies, TV, music, personal files |

### Why Single Filesystem Matters

All *arr apps and the download client must share a single NFS mount at the same path (`/data`). This enables hardlinks: when Sonarr/Radarr "import" a completed download, they create a hardlink from `torrents/` to `media/` instead of copying. This is instant, uses zero additional disk space, and is the standard recommended by TRaSH Guides.

### ZFS Configuration

```
Dataset: hdd-mirror/media-data
  compression=lz4       # ~1.2x ratio on media metadata, minimal CPU cost
  atime=off             # No access time updates (significant NFS performance gain)
  recordsize=1M         # Large sequential reads (video streaming)
  xattr=sa              # Store extended attributes in inodes (NFS performance)
```

### Folder Structure (TRaSH Guides Standard)

```
/data                              # NFS mount (hdd-mirror/media-data)
├── torrents/
│   ├── movies/
│   └── tv/
├── usenet/                        # Future use (SABnzbd)
│   ├── movies/
│   └── tv/
├── media/
│   ├── movies/                    # Radarr hardlinks completed downloads here
│   ├── tv/                        # Sonarr hardlinks completed downloads here
│   ├── music/                     # Personal uploads, read by Navidrome + Jellyfin
│   └── personal/
│       ├── videos/                # Home videos
│       └── photos/                # Phone photos
└── config/                        # App configs (SQLite DBs, settings)
    ├── sonarr/
    ├── radarr/
    ├── prowlarr/
    ├── bazarr/
    ├── qbittorrent/
    ├── jellyfin/
    ├── jellyseerr/
    ├── navidrome/
    └── filebrowser/
```

### Volume Mounts Per App

| App | Mount | Path | Access |
|-----|-------|------|--------|
| qBittorrent | NFS | `/data` (full) | RWX — writes to `torrents/` |
| Sonarr | NFS | `/data` (full) | RWX — reads `torrents/`, hardlinks to `media/tv/` |
| Radarr | NFS | `/data` (full) | RWX — reads `torrents/`, hardlinks to `media/movies/` |
| Prowlarr | NFS | `/data/config/prowlarr` | RWO — config only, no media I/O |
| Bazarr | NFS | `/data` (full) | RWX — reads `media/`, writes `.srt` files alongside |
| Jellyfin | NFS | `/data` (full) | RWX — reads `media/` libraries |
| Jellyseerr | NFS | `/data/config/jellyseerr` | RWO — config only |
| Navidrome | NFS | `/data/media/music` (RO) + `/data/config/navidrome` (RW) | Split mount |
| Filebrowser | NFS | `/data/media` | RWX — upload target for personal media |

---

## Application Stack

### Data Flow

```
                    ┌──────────────┐
                    │  Jellyseerr  │  ← Users browse & request content
                    └──────┬───────┘
                           │ HTTP API
                    ┌──────┴───────┐
               ┌────┤              ├────┐
               │    │   Prowlarr   │    │
               │    └──────┬───────┘    │
               │           │            │
          ┌────▼───┐  search/push  ┌────▼───┐
          │ Sonarr │◄──────────────► Radarr │
          └────┬───┘               └────┬───┘
               │     HTTP API :8080     │
               └──────────┬─────────────┘
                    ┌─────▼──────┐
                    │qBittorrent │ ← ALL traffic via Gluetun VPN
                    │  +Gluetun  │
                    └─────┬──────┘
                          │ writes to /data/torrents/
                          ▼
              ┌───────────────────────┐
              │   NFS: /data          │
              │  (hdd-mirror ZFS)     │
              └───────────┬───────────┘
                          │ hardlinks to /data/media/
                          ▼
          ┌─────────┬─────────┬──────────┐
          │Jellyfin │Navidrome│Filebrowser│  ← Users consume content
          └─────────┴─────────┴──────────┘
                          │
                    ┌─────▼──────┐
                    │   Bazarr   │  ← Watches media/, downloads subtitles
                    └────────────┘
```

### User-Facing Apps

**Jellyfin** (v10.10.3) — Primary streaming interface. Multi-user profiles with per-library permissions. Libraries: Movies, TV Shows, Music, Personal Videos.

| Setting | Value |
|---------|-------|
| Image | `jellyfin/jellyfin:10.10.3` |
| GPU | RTX 3060 via NVIDIA device plugin (NVENC hardware transcoding) |
| Plugins | Open Subtitles, TMDb Box Sets, Intro Skipper, Merge Versions, Playback Reporting |
| Fallback | Software transcoding (CPU) if GPU not yet passed through |

**Jellyseerr** — Content request portal. Users browse trending content, search, and click "Request." Requests auto-trigger Sonarr/Radarr downloads. Integrates with Jellyfin user accounts for SSO.

**Navidrome** — Dedicated music server exposing the Subsonic API. Shares the same music directory as Jellyfin via NFS. Lightweight Go binary. Mobile clients: Finamp (iOS), Symfonium (Android).

**Filebrowser** — Web-based file upload for personal media (music, photos, home videos). PWA-capable for phone use. Points at `/data/media` as the upload root.

### Backend Apps (Admin-Only)

| App | Purpose |
|-----|---------|
| Sonarr | TV series automation — monitors shows, grabs new episodes, renames and organizes into `media/tv/` |
| Radarr | Movie automation — same workflow as Sonarr for movies into `media/movies/` |
| Prowlarr | Indexer hub — manages Usenet/torrent indexer sources, pushes configs to Sonarr/Radarr |
| Bazarr | Subtitle automation — monitors Sonarr/Radarr libraries, auto-downloads matching subtitles |
| qBittorrent | Download client — ALL traffic routed through Gluetun VPN sidecar |
| Gluetun | VPN sidecar container (WireGuard protocol) — runs in same pod as qBittorrent, kill switch behavior |
| Recyclarr | Syncs TRaSH Guides quality profiles to Sonarr/Radarr — runs as a CronJob, not a persistent service |

---

## Network Architecture

### Inter-App Communication

All communication between backend apps uses K8s ClusterIP services over HTTP API.

| Source | Target | Port | Purpose |
|--------|--------|------|---------|
| Prowlarr | Sonarr, Radarr | 8989, 7878 | Push indexer configurations |
| Sonarr, Radarr | qBittorrent | 8080 | Send download requests |
| Sonarr, Radarr | Prowlarr | 9696 | Search indexers |
| Bazarr | Sonarr, Radarr | 8989, 7878 | Query media libraries for subtitle matching |
| Jellyseerr | Sonarr, Radarr, Jellyfin | 8989, 7878, 8096 | Forward requests, sync user accounts |

Jellyfin, Navidrome, and Filebrowser have no API dependencies on other apps — they read/write the filesystem directly.

### VPN Isolation (Critical)

qBittorrent MUST NOT have direct internet access. All its traffic goes through the Gluetun sidecar.

```
qBittorrent pod:
  ├── gluetun container (WireGuard tunnel to VPN provider)
  │     └── FIREWALL_INPUT_PORTS=8080  (allows cluster → qBit web UI)
  └── qbittorrent container (network: shared with gluetun)
```

**NetworkPolicy** on the qBittorrent pod enforces:
- Egress: ONLY to VPN provider IP (WireGuard endpoint)
- Egress: DNS to kube-dns (UDP 53) for internal service resolution
- Ingress: from `media` namespace pods on port 8080
- All other egress DENIED — if VPN drops, qBittorrent has no connectivity (kill switch)

VPN provider: user's choice. Mullvad or ProtonVPN recommended (both support WireGuard, no logs).

### Exposure Map

| App | Access | Method | URL | Auth |
|-----|--------|--------|-----|------|
| Jellyfin | Public | Pangolin | `watch.home-infra.net` | Jellyfin built-in accounts |
| Jellyseerr | Public | Pangolin | `request.home-infra.net` | Jellyfin SSO |
| Navidrome | Public | Pangolin | `music.home-infra.net` | Navidrome built-in accounts |
| Filebrowser | Public | Pangolin | `files.home-infra.net` | Filebrowser built-in auth |
| Sonarr | LAN only | Cilium LB-IPAM | `10.10.10.x` | Admin only |
| Radarr | LAN only | Cilium LB-IPAM | `10.10.10.x` | Admin only |
| Prowlarr | LAN only | Cilium LB-IPAM | `10.10.10.x` | Admin only |
| Bazarr | LAN only | Cilium LB-IPAM | `10.10.10.x` | Admin only |
| qBittorrent | LAN only | Cilium LB-IPAM | `10.10.10.x` | Admin only |

---

## K8s Resource Allocation

All resources deployed in namespace `media`.

| App | CPU Req | Mem Req | CPU Limit | Mem Limit | Notes |
|-----|---------|---------|-----------|-----------|-------|
| qBittorrent + Gluetun | 500m | 512Mi | 2000m | 1Gi | Sidecar pod |
| Sonarr | 250m | 512Mi | 1000m | 1Gi | |
| Radarr | 250m | 512Mi | 1000m | 1Gi | |
| Prowlarr | 100m | 256Mi | 500m | 512Mi | |
| Bazarr | 100m | 256Mi | 500m | 512Mi | |
| Jellyfin | 1000m | 2Gi | 4000m | 4Gi | + `nvidia.com/gpu: 1` |
| Jellyseerr | 250m | 512Mi | 1000m | 1Gi | |
| Navidrome | 100m | 128Mi | 500m | 256Mi | |
| Filebrowser | 100m | 128Mi | 500m | 256Mi | |
| **Total requests** | **2650m** | **4.75Gi** | | | Well within 56-core/128GB capacity |

### GPU Passthrough Requirements

1. RTX 3060 passed through from Proxmox to one Talos worker VM (PCI passthrough, IOMMU enabled)
2. Talos worker built with NVIDIA schematic (`nvidia-open-gpu-kernel-modules-lts`, `nvidia-container-toolkit-lts`)
3. NVIDIA device plugin DaemonSet deployed in K8s — exposes `nvidia.com/gpu` resource
4. Jellyfin pod uses `nodeAffinity` to schedule on the GPU-equipped worker
5. **Fallback**: deploy Jellyfin without GPU first. Software transcoding works but is CPU-heavy for multiple simultaneous streams. GPU can be added later without redeploying.

---

## User Access Model

| User | Jellyfin | Jellyseerr | Navidrome | Filebrowser |
|------|----------|-----------|-----------|-------------|
| Aaron (admin) | All libraries, server settings | Admin, auto-approve | Admin | Full access |
| Family | Movies, TV, Music, Personal | Can request, auto-approved | User account | No access |
| Friends | Movies, TV only | Can request, requires approval, 5/month limit | No access | No access |

---

## Backup Strategy

| Data | Classification | Method | Target | RPO |
|------|---------------|--------|--------|-----|
| App configs (SQLite DBs) | Important | Velero | AWS S3 | Daily |
| Downloaded movies/TV | Replaceable | No backup | — | — |
| Personal music | Irreplaceable | ZFS snapshots + rclone | Backblaze B2 | Daily |
| Personal photos/videos | Irreplaceable | ZFS snapshots + rclone | Backblaze B2 | Daily |
| Jellyfin metadata | Nice-to-have | Velero | AWS S3 | Daily |

**ZFS snapshots** on Proxmox host: daily at 03:00, 14-day retention. Protects against accidental deletion and corruption.

**rclone** sync from `/data/media/music/` and `/data/media/personal/` to a Backblaze B2 bucket. Runs on cron from the Proxmox host. Only irreplaceable personal media is backed up off-site — downloaded movies/TV can be re-acquired.

---

## Proxmox Host Setup (Manual Pre-Requisites)

These steps run on the `daytona` Proxmox host before any K8s resources are deployed.

### 1. Create ZFS Dataset

```bash
zfs create hdd-mirror/media-data
zfs set compression=lz4 hdd-mirror/media-data
zfs set atime=off hdd-mirror/media-data
zfs set recordsize=1M hdd-mirror/media-data
zfs set xattr=sa hdd-mirror/media-data
```

### 2. Create Folder Structure

```bash
mkdir -p /hdd-mirror/media-data/{torrents/{movies,tv},usenet/{movies,tv},media/{movies,tv,music,personal/{videos,photos}},config/{sonarr,radarr,prowlarr,bazarr,qbittorrent,jellyfin,jellyseerr,navidrome,filebrowser}}
chown -R 1000:1000 /hdd-mirror/media-data
```

UID 1000 matches the default user inside most *arr containers.

### 3. Install and Configure NFS

```bash
apt install nfs-kernel-server
echo '/hdd-mirror/media-data 10.10.10.0/16(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports
exportfs -ra
systemctl enable nfs-kernel-server
```

`no_root_squash` required so containers running as root can write. The export is restricted to the PROD VLAN (`10.10.10.0/16`).

### 4. ZFS Snapshot Cron

```bash
# /etc/cron.d/zfs-snapshots
0 3 * * * root zfs snapshot hdd-mirror/media-data@auto-$(date +\%Y\%m\%d) && zfs list -t snapshot -o name -H hdd-mirror/media-data | head -n -14 | xargs -r -n1 zfs destroy
```

Creates a daily snapshot and prunes snapshots older than 14 days.

---

## K8s Manifests

All manifests are deployed via ArgoCD using the app-of-apps pattern.

| File | Purpose |
|------|---------|
| `core/manifests/apps/media/namespace.yaml` | Namespace with labels |
| `core/manifests/apps/media/nfs-pv.yaml` | NFS PersistentVolume pointing to Proxmox host |
| `core/manifests/apps/media/nfs-pvc.yaml` | PersistentVolumeClaim (RWX, bound to NFS PV) |
| `core/manifests/apps/media/qbittorrent.yaml` | Deployment with Gluetun sidecar container |
| `core/manifests/apps/media/sonarr.yaml` | Deployment |
| `core/manifests/apps/media/radarr.yaml` | Deployment |
| `core/manifests/apps/media/prowlarr.yaml` | Deployment |
| `core/manifests/apps/media/bazarr.yaml` | Deployment |
| `core/manifests/apps/media/jellyfin.yaml` | Deployment with `nvidia.com/gpu: 1` resource request |
| `core/manifests/apps/media/jellyseerr.yaml` | Deployment |
| `core/manifests/apps/media/navidrome.yaml` | Deployment |
| `core/manifests/apps/media/filebrowser.yaml` | Deployment |
| `core/manifests/apps/media/services.yaml` | All Services (LoadBalancer for user-facing, ClusterIP for backend) |
| `core/manifests/apps/media/vpn-secret.yaml` | SOPS-encrypted VPN credentials (WireGuard private key, endpoint) |
| `core/manifests/apps/media/networkpolicy.yaml` | Cilium NetworkPolicy for qBittorrent VPN isolation |
| `core/manifests/argocd/apps/media.yaml` | ArgoCD Application (points at `core/manifests/apps/media/`) |

---

## Implementation Order

Steps marked **(manual)** require human action. Everything else is automated via ArgoCD after manifests are committed.

| Step | Action | Type |
|------|--------|------|
| 1 | ZFS dataset + NFS export + folder structure on Proxmox | Manual |
| 2 | NFS PV/PVC + namespace manifests | ArgoCD |
| 3 | VPN credentials — SOPS-encrypt WireGuard config into K8s Secret | Manual (encrypt), ArgoCD (deploy) |
| 4 | qBittorrent + Gluetun — verify VPN connectivity and kill switch | ArgoCD, then manual verification |
| 5 | Prowlarr — configure indexers via web UI | ArgoCD, then manual config |
| 6 | Sonarr + Radarr — connect to Prowlarr + qBittorrent, verify hardlinks work | ArgoCD, then manual config |
| 7 | Bazarr — connect to Sonarr/Radarr | ArgoCD, then manual config |
| 8 | Jellyfin — point at media libraries (initially without GPU) | ArgoCD, then manual config |
| 9 | Jellyseerr — connect to Jellyfin + Sonarr/Radarr | ArgoCD, then manual config |
| 10 | Navidrome — point at music directory | ArgoCD, then manual config |
| 11 | Filebrowser — point at media upload directory | ArgoCD |
| 12 | Pangolin resources — expose Jellyfin, Jellyseerr, Navidrome, Filebrowser | Manual (Pangolin dashboard) |
| 13 | GPU passthrough — RTX 3060 to Talos worker + NVIDIA device plugin | Manual |
| 14 | Backblaze B2 bucket + rclone cron on Proxmox | Manual |
| 15 | Recyclarr CronJob — TRaSH quality profiles synced to Sonarr/Radarr | ArgoCD |

---

## What This Replaces

| Service | Replaced By | Advantage |
|---------|------------|-----------|
| Netflix | Jellyfin + Sonarr/Radarr | No subscription, no content rotation, unlimited simultaneous streams |
| Spotify | Navidrome + personal music library | Own your music, no ads, Subsonic API for any mobile client |
| Google Photos | Filebrowser (now), Immich (future) | No tracking, no storage limits beyond physical hardware |
| YouTube (saved content) | Jellyfin personal videos library | Permanent storage, no takedowns or availability changes |

---

## Future Enhancements (Out of Scope)

These are noted for context but are not part of this design.

- **Immich** — full photo management platform (replaces Filebrowser for photos)
- **Lidarr** — automated music downloads (same pattern as Sonarr/Radarr)
- **Unpackerr** — handles compressed/archived releases
- **Notifiarr** — push notifications ("your movie is ready")
- **Jellystat** — streaming analytics and usage dashboards
- **Zitadel SSO** — unified authentication across all apps
