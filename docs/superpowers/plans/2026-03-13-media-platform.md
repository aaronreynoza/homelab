# Self-Hosted Media Platform Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a complete self-hosted media platform (Netflix/Spotify replacement) on K8s with automated content acquisition, hardware transcoding, and multi-user streaming.

**Architecture:** NFS from Proxmox ZFS for shared media storage, ArgoCD-managed deployments for all apps in `media` namespace, Gluetun VPN sidecar for download client isolation, Pangolin for public access.

**Tech Stack:** Jellyfin, Navidrome, Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, Gluetun, Jellyseerr, Filebrowser, Recyclarr, Cilium NetworkPolicy

**Spec:** `docs/superpowers/specs/2026-03-13-media-platform-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `docs/runbooks/media-storage-setup.md` (create) | Proxmox ZFS dataset + NFS export runbook |
| `core/manifests/apps/media/namespace.yaml` (create) | Namespace with pod-security privileged labels |
| `core/manifests/apps/media/nfs-pv.yaml` (create) | NFS PersistentVolume pointing to Proxmox host |
| `core/manifests/apps/media/nfs-pvc.yaml` (create) | PVC with RWX access bound to NFS PV |
| `core/manifests/argocd/apps/media.yaml` (create) | ArgoCD Application for media namespace |
| `core/manifests/apps/media/qbittorrent.yaml` (create) | Deployment with Gluetun VPN sidecar |
| `core/manifests/apps/media/networkpolicy.yaml` (create) | CiliumNetworkPolicy for VPN isolation |
| `core/manifests/apps/media/prowlarr.yaml` (create) | Prowlarr Deployment |
| `core/manifests/apps/media/sonarr.yaml` (create) | Sonarr Deployment |
| `core/manifests/apps/media/radarr.yaml` (create) | Radarr Deployment |
| `core/manifests/apps/media/bazarr.yaml` (create) | Bazarr Deployment |
| `core/manifests/apps/media/jellyfin.yaml` (create) | Jellyfin Deployment (GPU commented out initially) |
| `core/manifests/apps/media/jellyseerr.yaml` (create) | Jellyseerr Deployment |
| `core/manifests/apps/media/navidrome.yaml` (create) | Navidrome Deployment |
| `core/manifests/apps/media/filebrowser.yaml` (create) | Filebrowser Deployment |
| `core/manifests/apps/media/services.yaml` (create) | All Services (LoadBalancer + ClusterIP) |
| `core/manifests/apps/media/recyclarr.yaml` (create) | Recyclarr CronJob + ConfigMap |
| `docs/runbooks/media-stack-config.md` (create) | Post-deploy app configuration guide |
| `docs/runbooks/media-pangolin-setup.md` (create) | Pangolin resource creation guide |
| `docs/runbooks/media-backblaze-backup.md` (create) | Backblaze B2 rclone backup guide |

---

## Chunk 1: Storage Foundation

### Task 1: Proxmox ZFS Dataset and NFS Export (Manual Runbook)

**Files:**
- Create: `docs/runbooks/media-storage-setup.md`

**Context:** This is a manual runbook to be executed via SSH on the `daytona` Proxmox host. It creates the ZFS dataset with media-optimized tuning, the TRaSH Guides folder structure, NFS exports restricted to the PROD VLAN, and a snapshot cron. Must be completed before any K8s resources are deployed.

- [ ] **Step 1: Create `docs/runbooks/media-storage-setup.md`**

```markdown
# Media Storage Setup — Proxmox Host

Run all commands on `daytona` via SSH.

## Prerequisites
- `hdd-mirror` ZFS pool exists (`zpool status hdd-mirror`)
- Proxmox host has network access from PROD VLAN (10.10.10.0/16)

## 1. Create ZFS Dataset

```bash
zfs create hdd-mirror/media-data
zfs set compression=lz4 hdd-mirror/media-data
zfs set atime=off hdd-mirror/media-data
zfs set recordsize=1M hdd-mirror/media-data
zfs set xattr=sa hdd-mirror/media-data
```

## 2. Create Folder Structure (TRaSH Guides Standard)

```bash
mkdir -p /hdd-mirror/media-data/{torrents/{movies,tv},usenet/{movies,tv},media/{movies,tv,music,personal/{videos,photos}},config/{sonarr,radarr,prowlarr,bazarr,qbittorrent,jellyfin,jellyseerr,navidrome,filebrowser}}
chown -R 1000:1000 /hdd-mirror/media-data
```

UID 1000 matches the default user inside linuxserver.io containers.

## 3. Install and Configure NFS

```bash
apt install -y nfs-kernel-server
echo '/hdd-mirror/media-data 10.10.10.0/16(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports
exportfs -ra
systemctl enable --now nfs-kernel-server
```

`no_root_squash` required so containers running as root can write. Export restricted to PROD VLAN.

## 4. ZFS Snapshot Cron

```bash
cat > /etc/cron.d/zfs-media-snapshots << 'CRON'
# Daily ZFS snapshot at 03:00, keep 14 days
0 3 * * * root zfs snapshot hdd-mirror/media-data@auto-$(date +\%Y\%m\%d) && zfs list -t snapshot -o name -H hdd-mirror/media-data | head -n -14 | xargs -r -n1 zfs destroy
CRON
```

## 5. Verification

```bash
# Confirm dataset
zfs list hdd-mirror/media-data
zfs get compression,atime,recordsize,xattr hdd-mirror/media-data

# Confirm NFS export
showmount -e localhost

# Confirm folder structure
ls -la /hdd-mirror/media-data/
ls -la /hdd-mirror/media-data/media/
ls -la /hdd-mirror/media-data/config/

# Test NFS mount from a K8s node (SSH to a worker):
# mount -t nfs REDACTED_PVE_IP:/hdd-mirror/media-data /mnt/test
# ls /mnt/test
# umount /mnt/test
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/media-storage-setup.md
git commit -m "Add media storage setup runbook (ZFS + NFS on Proxmox)"
```

---

## Chunk 2: K8s Namespace + NFS Storage

### Task 2: K8s Namespace + NFS PV/PVC

**Files:**
- Create: `core/manifests/apps/media/namespace.yaml`
- Create: `core/manifests/apps/media/nfs-pv.yaml`
- Create: `core/manifests/apps/media/nfs-pvc.yaml`

**Context:** The media namespace needs `pod-security.kubernetes.io/enforce: privileged` because Gluetun requires `NET_ADMIN` capability and `/dev/net/tun`. The NFS PV points to daytona's management IP (`REDACTED_PVE_IP`) since K8s pods on VLAN 10 route through OPNSense which has a WAN-to-PROD pass rule. The PVC uses RWX so all media pods can mount it simultaneously.

- [ ] **Step 1: Create `core/manifests/apps/media/namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: media
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

- [ ] **Step 2: Create `core/manifests/apps/media/nfs-pv.yaml`**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-nfs-pv
  labels:
    app: media
spec:
  capacity:
    storage: 3Ti
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  nfs:
    server: REDACTED_PVE_IP
    path: /hdd-mirror/media-data
```

- [ ] **Step 3: Create `core/manifests/apps/media/nfs-pvc.yaml`**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media-nfs
  namespace: media
  labels:
    app: media
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  volumeName: media-nfs-pv
  resources:
    requests:
      storage: 3Ti
```

- [ ] **Step 4: Commit**

```bash
git add core/manifests/apps/media/namespace.yaml core/manifests/apps/media/nfs-pv.yaml core/manifests/apps/media/nfs-pvc.yaml
git commit -m "Add media namespace and NFS PV/PVC for Proxmox ZFS storage"
```

---

## Chunk 3: ArgoCD Application

### Task 3: ArgoCD Application

**Files:**
- Create: `core/manifests/argocd/apps/media.yaml`

**Context:** Follows the existing ArgoCD app-of-apps pattern. Uses sync-wave 10 (same as other application deployments), points to `core/manifests/apps/media`, and includes `managedNamespaceMetadata` with privileged pod-security labels (same pattern as velero.yaml). ServerSideApply is needed because of CiliumNetworkPolicy CRDs.

- [ ] **Step 1: Create `core/manifests/argocd/apps/media.yaml`**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: media
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/aaronreynoza/homelab.git
    targetRevision: main
    path: core/manifests/apps/media
  destination:
    server: https://kubernetes.default.svc
    namespace: media
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: privileged
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

- [ ] **Step 2: Commit**

```bash
git add core/manifests/argocd/apps/media.yaml
git commit -m "Add ArgoCD application for media namespace"
```

---

## Chunk 4: qBittorrent + Gluetun VPN

### Task 4: qBittorrent + Gluetun Deployment

**Files:**
- Create: `core/manifests/apps/media/qbittorrent.yaml`

**Context:** Two containers in one pod: Gluetun creates the VPN tunnel, qBittorrent shares its network namespace and routes all traffic through the tunnel. Gluetun needs `NET_ADMIN` capability and `/dev/net/tun` device. VPN credentials use placeholders that the user fills in manually (not SOPS-managed in this iteration). Both containers mount the full NFS PVC at `/data` so qBittorrent writes to `/data/torrents/`. Config is stored at `/data/config/qbittorrent` via subPath.

- [ ] **Step 1: Create `core/manifests/apps/media/qbittorrent.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qbittorrent
  namespace: media
  labels:
    app: qbittorrent
spec:
  replicas: 1
  selector:
    matchLabels:
      app: qbittorrent
  template:
    metadata:
      labels:
        app: qbittorrent
    spec:
      containers:
        - name: gluetun
          image: qmcgaw/gluetun:v3.39
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
          volumeMounts:
            - name: dev-tun
              mountPath: /dev/net/tun
          env:
            - name: VPN_SERVICE_PROVIDER
              value: "__VPN_PROVIDER__"
            - name: VPN_TYPE
              value: "wireguard"
            - name: WIREGUARD_PRIVATE_KEY
              value: "__WIREGUARD_PRIVATE_KEY__"
            - name: WIREGUARD_ADDRESSES
              value: "__WIREGUARD_ADDRESSES__"
            - name: SERVER_COUNTRIES
              value: "__SERVER_COUNTRIES__"
            - name: FIREWALL_INPUT_PORTS
              value: "8080"
          ports:
            - containerPort: 8080
              name: qbit-web
              protocol: TCP
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 30
            failureThreshold: 5
        - name: qbittorrent
          image: linuxserver/qbittorrent:4.6.7
          env:
            - name: PUID
              value: "1000"
            - name: PGID
              value: "1000"
            - name: TZ
              value: "America/Mexico_City"
            - name: WEBUI_PORT
              value: "8080"
          volumeMounts:
            - name: media-data
              mountPath: /data
            - name: media-data
              mountPath: /config
              subPath: config/qbittorrent
          resources:
            requests:
              cpu: 400m
              memory: 384Mi
            limits:
              cpu: 1500m
              memory: 768Mi
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
        - name: dev-tun
          hostPath:
            path: /dev/net/tun
            type: CharDevice
```

- [ ] **Step 2: Commit**

```bash
git add core/manifests/apps/media/qbittorrent.yaml
git commit -m "Add qBittorrent + Gluetun VPN sidecar deployment"
```

---

### Task 5: qBittorrent Service + NetworkPolicy

**Files:**
- Create: `core/manifests/apps/media/services.yaml`
- Create: `core/manifests/apps/media/networkpolicy.yaml`

**Context:** qBittorrent gets a ClusterIP service (admin-only, accessed via LAN). The CiliumNetworkPolicy enforces VPN isolation: the qBittorrent pod can only egress to the VPN endpoint and kube-dns, all other egress is denied (kill switch behavior). Ingress is allowed from within the media namespace on port 8080.

- [ ] **Step 1: Create `core/manifests/apps/media/services.yaml`** (initial content, will be appended in later tasks)

```yaml
# qBittorrent — ClusterIP (admin-only, accessed via port-forward or LAN)
apiVersion: v1
kind: Service
metadata:
  name: qbittorrent
  namespace: media
  labels:
    app: qbittorrent
spec:
  type: ClusterIP
  selector:
    app: qbittorrent
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
```

- [ ] **Step 2: Create `core/manifests/apps/media/networkpolicy.yaml`**

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: qbittorrent-vpn-isolation
  namespace: media
spec:
  endpointSelector:
    matchLabels:
      app: qbittorrent
  egress:
    # Allow DNS to kube-dns
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    # Allow VPN endpoint — replace __VPN_ENDPOINT_IP__ with your VPN provider's IP
    - toCIDR:
        - "__VPN_ENDPOINT_IP__/32"
      toPorts:
        - ports:
            - port: "51820"
              protocol: UDP
  ingress:
    # Allow media namespace pods to reach qBittorrent web UI
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: media
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/services.yaml core/manifests/apps/media/networkpolicy.yaml
git commit -m "Add qBittorrent service and CiliumNetworkPolicy for VPN isolation"
```

---

## Chunk 5: Indexer + Automation Apps

### Task 6: Prowlarr Deployment + Service

**Files:**
- Modify: `core/manifests/apps/media/services.yaml` (append)
- Create: `core/manifests/apps/media/prowlarr.yaml`

**Context:** Prowlarr manages indexer sources and pushes configurations to Sonarr/Radarr. It only needs its config directory (SQLite DB), not the full NFS mount. Port 9696.

- [ ] **Step 1: Create `core/manifests/apps/media/prowlarr.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prowlarr
  namespace: media
  labels:
    app: prowlarr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prowlarr
  template:
    metadata:
      labels:
        app: prowlarr
    spec:
      containers:
        - name: prowlarr
          image: linuxserver/prowlarr:1.28.2
          env:
            - name: PUID
              value: "1000"
            - name: PGID
              value: "1000"
            - name: TZ
              value: "America/Mexico_City"
          ports:
            - containerPort: 9696
          volumeMounts:
            - name: media-data
              mountPath: /config
              subPath: config/prowlarr
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /ping
              port: 9696
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /ping
              port: 9696
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Prowlarr service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Prowlarr — ClusterIP (admin-only)
apiVersion: v1
kind: Service
metadata:
  name: prowlarr
  namespace: media
  labels:
    app: prowlarr
spec:
  type: ClusterIP
  selector:
    app: prowlarr
  ports:
    - port: 9696
      targetPort: 9696
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/prowlarr.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Prowlarr deployment and service"
```

---

### Task 7: Sonarr Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/sonarr.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Sonarr automates TV series acquisition. It needs the full NFS mount at `/data` to read from `torrents/` and hardlink to `media/tv/`. Config stored at `/data/config/sonarr` via subPath. Port 8989.

- [ ] **Step 1: Create `core/manifests/apps/media/sonarr.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarr
  namespace: media
  labels:
    app: sonarr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarr
  template:
    metadata:
      labels:
        app: sonarr
    spec:
      containers:
        - name: sonarr
          image: linuxserver/sonarr:4.0.11
          env:
            - name: PUID
              value: "1000"
            - name: PGID
              value: "1000"
            - name: TZ
              value: "America/Mexico_City"
          ports:
            - containerPort: 8989
          volumeMounts:
            - name: media-data
              mountPath: /data
            - name: media-data
              mountPath: /config
              subPath: config/sonarr
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /ping
              port: 8989
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /ping
              port: 8989
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Sonarr service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Sonarr — ClusterIP (admin-only)
apiVersion: v1
kind: Service
metadata:
  name: sonarr
  namespace: media
  labels:
    app: sonarr
spec:
  type: ClusterIP
  selector:
    app: sonarr
  ports:
    - port: 8989
      targetPort: 8989
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/sonarr.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Sonarr deployment and service"
```

---

### Task 8: Radarr Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/radarr.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Radarr automates movie acquisition. Same pattern as Sonarr but port 7878, config subPath `config/radarr`, hardlinks to `media/movies/`.

- [ ] **Step 1: Create `core/manifests/apps/media/radarr.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: radarr
  namespace: media
  labels:
    app: radarr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: radarr
  template:
    metadata:
      labels:
        app: radarr
    spec:
      containers:
        - name: radarr
          image: linuxserver/radarr:5.14.0
          env:
            - name: PUID
              value: "1000"
            - name: PGID
              value: "1000"
            - name: TZ
              value: "America/Mexico_City"
          ports:
            - containerPort: 7878
          volumeMounts:
            - name: media-data
              mountPath: /data
            - name: media-data
              mountPath: /config
              subPath: config/radarr
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /ping
              port: 7878
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /ping
              port: 7878
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Radarr service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Radarr — ClusterIP (admin-only)
apiVersion: v1
kind: Service
metadata:
  name: radarr
  namespace: media
  labels:
    app: radarr
spec:
  type: ClusterIP
  selector:
    app: radarr
  ports:
    - port: 7878
      targetPort: 7878
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/radarr.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Radarr deployment and service"
```

---

### Task 9: Bazarr Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/bazarr.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Bazarr automates subtitle downloads. It needs the full NFS mount at `/data` to read media files and write `.srt` files alongside them. Config stored at `/data/config/bazarr` via subPath. Port 6767.

- [ ] **Step 1: Create `core/manifests/apps/media/bazarr.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bazarr
  namespace: media
  labels:
    app: bazarr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bazarr
  template:
    metadata:
      labels:
        app: bazarr
    spec:
      containers:
        - name: bazarr
          image: linuxserver/bazarr:1.4.5
          env:
            - name: PUID
              value: "1000"
            - name: PGID
              value: "1000"
            - name: TZ
              value: "America/Mexico_City"
          ports:
            - containerPort: 6767
          volumeMounts:
            - name: media-data
              mountPath: /data
            - name: media-data
              mountPath: /config
              subPath: config/bazarr
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /api/system/health
              port: 6767
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /api/system/health
              port: 6767
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Bazarr service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Bazarr — ClusterIP (admin-only)
apiVersion: v1
kind: Service
metadata:
  name: bazarr
  namespace: media
  labels:
    app: bazarr
spec:
  type: ClusterIP
  selector:
    app: bazarr
  ports:
    - port: 6767
      targetPort: 6767
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/bazarr.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Bazarr deployment and service"
```

---

## Chunk 6: User-Facing Apps

### Task 10: Jellyfin Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/jellyfin.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Jellyfin is the primary streaming interface. It reads media from NFS and serves it to users. GPU passthrough (`nvidia.com/gpu: 1`) is commented out for initial deployment — software transcoding works but is CPU-heavy. The GPU can be enabled later without redeploying. Jellyfin gets a LoadBalancer service since it is user-facing and will be exposed via Pangolin.

- [ ] **Step 1: Create `core/manifests/apps/media/jellyfin.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jellyfin
  namespace: media
  labels:
    app: jellyfin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jellyfin
  template:
    metadata:
      labels:
        app: jellyfin
    spec:
      containers:
        - name: jellyfin
          image: jellyfin/jellyfin:10.10.3
          env:
            - name: JELLYFIN_PublishedServerUrl
              value: "https://watch.home-infra.net"
          ports:
            - containerPort: 8096
          volumeMounts:
            - name: media-data
              mountPath: /media
              subPath: media
            - name: media-data
              mountPath: /config
              subPath: config/jellyfin
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
            limits:
              cpu: 4000m
              memory: 4Gi
              # Uncomment when GPU passthrough is configured:
              # nvidia.com/gpu: 1
          livenessProbe:
            httpGet:
              path: /health
              port: 8096
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 8096
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Jellyfin service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Jellyfin — LoadBalancer (user-facing, exposed via Pangolin)
apiVersion: v1
kind: Service
metadata:
  name: jellyfin
  namespace: media
  labels:
    app: jellyfin
spec:
  type: LoadBalancer
  selector:
    app: jellyfin
  ports:
    - port: 8096
      targetPort: 8096
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/jellyfin.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Jellyfin deployment and LoadBalancer service"
```

---

### Task 11: Jellyseerr Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/jellyseerr.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Jellyseerr is the content request portal. Users browse trending content and submit requests that auto-trigger Sonarr/Radarr downloads. It integrates with Jellyfin for user SSO. Gets a LoadBalancer service for Pangolin exposure.

- [ ] **Step 1: Create `core/manifests/apps/media/jellyseerr.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jellyseerr
  namespace: media
  labels:
    app: jellyseerr
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jellyseerr
  template:
    metadata:
      labels:
        app: jellyseerr
    spec:
      containers:
        - name: jellyseerr
          image: fallenbagel/jellyseerr:2.3.0
          env:
            - name: TZ
              value: "America/Mexico_City"
          ports:
            - containerPort: 5055
          volumeMounts:
            - name: media-data
              mountPath: /app/config
              subPath: config/jellyseerr
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /api/v1/status
              port: 5055
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /api/v1/status
              port: 5055
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Jellyseerr service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Jellyseerr — LoadBalancer (user-facing, exposed via Pangolin)
apiVersion: v1
kind: Service
metadata:
  name: jellyseerr
  namespace: media
  labels:
    app: jellyseerr
spec:
  type: LoadBalancer
  selector:
    app: jellyseerr
  ports:
    - port: 5055
      targetPort: 5055
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/jellyseerr.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Jellyseerr deployment and LoadBalancer service"
```

---

### Task 12: Navidrome Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/navidrome.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Navidrome is a dedicated music server exposing the Subsonic API. It has a split mount: music directory is read-only (subPath `media/music`), and its config/DB directory is read-write (subPath `config/navidrome`). Gets a LoadBalancer service for Pangolin exposure.

- [ ] **Step 1: Create `core/manifests/apps/media/navidrome.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: navidrome
  namespace: media
  labels:
    app: navidrome
spec:
  replicas: 1
  selector:
    matchLabels:
      app: navidrome
  template:
    metadata:
      labels:
        app: navidrome
    spec:
      containers:
        - name: navidrome
          image: deluan/navidrome:0.53.3
          env:
            - name: ND_MUSICFOLDER
              value: "/music"
            - name: ND_DATAFOLDER
              value: "/data"
          ports:
            - containerPort: 4533
          volumeMounts:
            - name: media-data
              mountPath: /music
              subPath: media/music
              readOnly: true
            - name: media-data
              mountPath: /data
              subPath: config/navidrome
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /ping
              port: 4533
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /ping
              port: 4533
            initialDelaySeconds: 5
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Navidrome service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Navidrome — LoadBalancer (user-facing, exposed via Pangolin)
apiVersion: v1
kind: Service
metadata:
  name: navidrome
  namespace: media
  labels:
    app: navidrome
spec:
  type: LoadBalancer
  selector:
    app: navidrome
  ports:
    - port: 4533
      targetPort: 4533
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/navidrome.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Navidrome deployment and LoadBalancer service"
```

---

### Task 13: Filebrowser Deployment + Service

**Files:**
- Create: `core/manifests/apps/media/filebrowser.yaml`
- Modify: `core/manifests/apps/media/services.yaml` (append)

**Context:** Filebrowser provides web-based file upload for personal media (music, photos, home videos). It mounts `/data/media` as `/srv` (its serving root). Gets a LoadBalancer service for Pangolin exposure. Default credentials are admin/admin — must be changed immediately after first login.

- [ ] **Step 1: Create `core/manifests/apps/media/filebrowser.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: filebrowser
  namespace: media
  labels:
    app: filebrowser
spec:
  replicas: 1
  selector:
    matchLabels:
      app: filebrowser
  template:
    metadata:
      labels:
        app: filebrowser
    spec:
      containers:
        - name: filebrowser
          image: filebrowser/filebrowser:v2.31.2
          ports:
            - containerPort: 80
          volumeMounts:
            - name: media-data
              mountPath: /srv
              subPath: media
            - name: media-data
              mountPath: /database
              subPath: config/filebrowser
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
      volumes:
        - name: media-data
          persistentVolumeClaim:
            claimName: media-nfs
```

- [ ] **Step 2: Append Filebrowser service to `core/manifests/apps/media/services.yaml`**

Append the following to the end of the file:

```yaml
---
# Filebrowser — LoadBalancer (user-facing, exposed via Pangolin)
apiVersion: v1
kind: Service
metadata:
  name: filebrowser
  namespace: media
  labels:
    app: filebrowser
spec:
  type: LoadBalancer
  selector:
    app: filebrowser
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add core/manifests/apps/media/filebrowser.yaml core/manifests/apps/media/services.yaml
git commit -m "Add Filebrowser deployment and LoadBalancer service"
```

---

## Chunk 7: Recyclarr CronJob

### Task 14: Recyclarr CronJob

**Files:**
- Create: `core/manifests/apps/media/recyclarr.yaml`

**Context:** Recyclarr syncs TRaSH Guides quality profiles to Sonarr and Radarr. It runs as a CronJob (daily at 4 AM), not a persistent service. The ConfigMap contains a `recyclarr.yml` with base TRaSH config pointing to the in-cluster Sonarr/Radarr services. API keys are placeholders — the user fills them in after Sonarr/Radarr generate their keys on first boot.

- [ ] **Step 1: Create `core/manifests/apps/media/recyclarr.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: recyclarr-config
  namespace: media
data:
  recyclarr.yml: |
    sonarr:
      series:
        base_url: http://sonarr.media.svc.cluster.local:8989
        api_key: __SONARR_API_KEY__
        quality_definition:
          type: series
        quality_profiles:
          - name: WEB-DL (1080p)
            reset_unmatched_scores:
              enabled: true
            upgrade:
              allowed: true
              until_quality: WEB 1080p
              until_score: 10000
        custom_formats:
          - trash_ids:
              - 32b367365729d530ca1c124a0b180c64  # Bad Dual Groups
              - 82d40da2bc6923f41e14394075dd4b03  # No-RlsGroup
              - e1a997ddb54e3ecbfe06341ad323c458  # Obfuscated
              - 06d66ab109d4d2eddb2794d21526d140  # Retags
            assign_scores_to:
              - name: WEB-DL (1080p)

    radarr:
      movies:
        base_url: http://radarr.media.svc.cluster.local:7878
        api_key: __RADARR_API_KEY__
        quality_definition:
          type: movie
        quality_profiles:
          - name: WEB-DL (1080p)
            reset_unmatched_scores:
              enabled: true
            upgrade:
              allowed: true
              until_quality: WEB 1080p
              until_score: 10000
        custom_formats:
          - trash_ids:
              - b6832f586342ef70d9c128d40c07b872  # Bad Dual Groups
              - 90cedc1fea7ea5d11298bebd3d1d3223  # EVO (no WEBDL)
              - ae9b7c9ebde1f3bd336a8cbd1ec4c5e5  # No-RlsGroup
              - 7357cf5161efbf8c4d5d0c30b4815ee2  # Obfuscated
              - 5c44f52a8714fdd79bb4d98e2673be1f  # Retags
            assign_scores_to:
              - name: WEB-DL (1080p)
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: recyclarr
  namespace: media
  labels:
    app: recyclarr
spec:
  schedule: "0 4 * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: recyclarr
        spec:
          restartPolicy: OnFailure
          containers:
            - name: recyclarr
              image: recyclarr/recyclarr:7.4.0
              args: ["sync"]
              volumeMounts:
                - name: config
                  mountPath: /config/recyclarr.yml
                  subPath: recyclarr.yml
              resources:
                requests:
                  cpu: 50m
                  memory: 64Mi
                limits:
                  cpu: 200m
                  memory: 128Mi
          volumes:
            - name: config
              configMap:
                name: recyclarr-config
```

- [ ] **Step 2: Commit**

```bash
git add core/manifests/apps/media/recyclarr.yaml
git commit -m "Add Recyclarr CronJob with TRaSH Guides quality profiles"
```

---

## Chunk 8: Runbooks

### Task 15: Media Stack Configuration Runbook

**Files:**
- Create: `docs/runbooks/media-stack-config.md`

**Context:** After all K8s resources are deployed, each app needs manual first-time configuration via its web UI. This runbook provides the exact steps in dependency order.

- [ ] **Step 1: Create `docs/runbooks/media-stack-config.md`**

```markdown
# Media Stack Configuration — Post-Deploy Web UI Setup

After all media stack pods are running, configure each app via its web UI. Follow this order — later apps depend on earlier ones being configured first.

## Prerequisites

- All pods in `media` namespace are Running: `kubectl get pods -n media`
- NFS PVC is bound: `kubectl get pvc -n media`
- For LAN access, ensure static route to PROD VLAN: `sudo route add -net 10.10.10.0/16 REDACTED_OPNSENSE_IP`

## 1. qBittorrent

Access: `http://<qbittorrent-service-ip>:8080`

1. Log in (default: admin / check container logs for generated password: `kubectl logs -n media deploy/qbittorrent -c qbittorrent | grep password`)
2. Settings > Downloads:
   - Default Save Path: `/data/torrents`
   - Keep incomplete torrents in: `/data/torrents/incomplete`
3. Settings > Connection:
   - Verify peer connections work (VPN is active)
4. Settings > Web UI:
   - Change default password
5. **Verify VPN is working:**
   ```bash
   kubectl exec -n media deploy/qbittorrent -c gluetun -- wget -qO- https://ipinfo.io
   ```
   The IP should NOT be your home IP — it should be the VPN provider's IP.

## 2. Prowlarr

Access: `http://<prowlarr-service-ip>:9696`

1. Set authentication (Settings > General)
2. Add indexers (Indexers > Add):
   - Add your preferred torrent indexers
   - Test each indexer after adding
3. Note: Prowlarr will automatically push indexer configs to Sonarr/Radarr once they are connected (step 3).

## 3. Sonarr

Access: `http://<sonarr-service-ip>:8989`

1. Set authentication (Settings > General)
2. Settings > Media Management:
   - Root Folder: `/data/media/tv`
   - Enable "Use Hardlinks instead of Copy"
3. Settings > Download Clients > Add:
   - Type: qBittorrent
   - Host: `qbittorrent.media.svc.cluster.local`
   - Port: 8080
   - Username/Password from step 1
   - Category: `tv`
4. Settings > General > Copy API Key (needed for Prowlarr, Bazarr, Jellyseerr, Recyclarr)
5. Go to Prowlarr > Settings > Apps > Add Sonarr:
   - Prowlarr Server: `http://prowlarr.media.svc.cluster.local:9696`
   - Sonarr Server: `http://sonarr.media.svc.cluster.local:8989`
   - API Key: from step 4

## 4. Radarr

Access: `http://<radarr-service-ip>:7878`

1. Set authentication (Settings > General)
2. Settings > Media Management:
   - Root Folder: `/data/media/movies`
   - Enable "Use Hardlinks instead of Copy"
3. Settings > Download Clients > Add:
   - Type: qBittorrent
   - Host: `qbittorrent.media.svc.cluster.local`
   - Port: 8080
   - Username/Password from step 1
   - Category: `movies`
4. Settings > General > Copy API Key (needed for Prowlarr, Bazarr, Jellyseerr, Recyclarr)
5. Go to Prowlarr > Settings > Apps > Add Radarr:
   - Prowlarr Server: `http://prowlarr.media.svc.cluster.local:9696`
   - Radarr Server: `http://radarr.media.svc.cluster.local:7878`
   - API Key: from step 4

## 5. Bazarr

Access: `http://<bazarr-service-ip>:6767`

1. Settings > Sonarr:
   - Host: `sonarr.media.svc.cluster.local`
   - Port: 8989
   - API Key: from Sonarr step 4
2. Settings > Radarr:
   - Host: `radarr.media.svc.cluster.local`
   - Port: 7878
   - API Key: from Radarr step 4
3. Settings > Providers:
   - Add OpenSubtitles.com (requires free account)
   - Add Subscene or other providers as desired
4. Settings > Languages:
   - Set desired languages (English, Spanish, etc.)

## 6. Jellyfin

Access: `http://<jellyfin-service-ip>:8096`

1. Initial setup wizard:
   - Create admin user
   - Set preferred language
2. Add libraries:
   - Movies: Content type "Movies", path `/media/movies`
   - TV Shows: Content type "Shows", path `/media/tv`
   - Music: Content type "Music", path `/media/music`
   - Personal Videos: Content type "Movies" or "Mixed", path `/media/personal/videos`
3. Settings > Playback:
   - If GPU is available: enable NVENC hardware transcoding
   - If not: leave at software transcoding (works but CPU-heavy)
4. Create additional user accounts per the access model in the spec
5. Install plugins (Dashboard > Plugins > Catalog):
   - Open Subtitles
   - TMDb Box Sets
   - Playback Reporting

## 7. Jellyseerr

Access: `http://<jellyseerr-service-ip>:5055`

1. Initial setup:
   - Select "Use your Jellyfin account" for sign-in
   - Jellyfin URL: `http://jellyfin.media.svc.cluster.local:8096`
   - Sign in with Jellyfin admin account
2. Add Sonarr:
   - Hostname: `sonarr.media.svc.cluster.local`
   - Port: 8989
   - API Key: from Sonarr step 4
   - Root Folder: `/data/media/tv`
   - Quality Profile: select preferred profile
3. Add Radarr:
   - Hostname: `radarr.media.svc.cluster.local`
   - Port: 7878
   - API Key: from Radarr step 4
   - Root Folder: `/data/media/movies`
   - Quality Profile: select preferred profile
4. Settings > Users:
   - Import Jellyfin users
   - Set permissions per user (auto-approve for family, manual for friends)
   - Set request limits for friends (5/month)

## 8. Navidrome

Access: `http://<navidrome-service-ip>:4533`

1. First login creates the admin account — choose a strong password
2. Verify music library loads from `/music`
3. Create additional user accounts as needed
4. Recommended mobile clients:
   - iOS: Finamp (free, open source)
   - Android: Symfonium (paid, best UX) or Subtracks (free)

## 9. Filebrowser

Access: `http://<filebrowser-service-ip>:80`

1. Default login: `admin` / `admin` — **change immediately**
2. Verify `/srv` shows the media directory structure (movies/, tv/, music/, personal/)
3. Settings > User Management:
   - Create user accounts as needed
   - Set per-user scope (e.g., restrict family to `/personal/` only)

## 10. Verify Hardlinks

After downloading a test item via Sonarr or Radarr:

```bash
# SSH to a node or exec into a pod with /data mounted
kubectl exec -n media deploy/sonarr -- ls -la /data/media/tv/
# Check link count — should be > 1 for imported files
kubectl exec -n media deploy/sonarr -- stat /data/media/tv/<show>/<episode>
```

If link count is 1, hardlinks are not working. Check:
- All apps mount the same NFS PVC at `/data`
- Sonarr/Radarr have "Use Hardlinks" enabled
- Download and media directories are on the same filesystem

## 11. Update Recyclarr API Keys

After obtaining API keys from Sonarr and Radarr:

```bash
kubectl edit configmap recyclarr-config -n media
```

Replace `__SONARR_API_KEY__` and `__RADARR_API_KEY__` with actual values. Then trigger a manual sync:

```bash
kubectl create job --from=cronjob/recyclarr recyclarr-manual -n media
kubectl logs -n media job/recyclarr-manual -f
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/media-stack-config.md
git commit -m "Add media stack post-deploy configuration runbook"
```

---

### Task 16: Pangolin Exposure Runbook

**Files:**
- Create: `docs/runbooks/media-pangolin-setup.md`

**Context:** Manual steps in the Pangolin dashboard to create resources that expose the user-facing media apps publicly. Each resource maps a subdomain to a K8s LoadBalancer IP.

- [ ] **Step 1: Create `docs/runbooks/media-pangolin-setup.md`**

```markdown
# Media Stack — Pangolin Exposure Setup

Create Pangolin resources for each user-facing media app. All resources route through the Vultr VPS (REDACTED_VPS_IP) and terminate at the K8s LoadBalancer IPs assigned by Cilium LB-IPAM.

## Prerequisites

- Media stack pods are running and services have LoadBalancer IPs assigned
- Get the assigned IPs: `kubectl get svc -n media`
- Pangolin dashboard is accessible
- DNS for `*.home-infra.net` points to the Pangolin VPS

## Resources to Create

For each resource below, go to Pangolin Dashboard > Sites > Aaron Homelab > Resources > Add Resource.

### 1. Jellyfin — watch.home-infra.net

| Field | Value |
|-------|-------|
| Domain | `watch.home-infra.net` |
| Target | `http://<jellyfin-lb-ip>:8096` |
| SSL | Auto (Let's Encrypt) |
| Websockets | Enabled (required for Jellyfin playback) |

### 2. Jellyseerr — request.home-infra.net

| Field | Value |
|-------|-------|
| Domain | `request.home-infra.net` |
| Target | `http://<jellyseerr-lb-ip>:5055` |
| SSL | Auto (Let's Encrypt) |
| Websockets | Enabled |

### 3. Navidrome — music.home-infra.net

| Field | Value |
|-------|-------|
| Domain | `music.home-infra.net` |
| Target | `http://<navidrome-lb-ip>:4533` |
| SSL | Auto (Let's Encrypt) |
| Websockets | Enabled (Subsonic API streaming) |

### 4. Filebrowser — files.home-infra.net

| Field | Value |
|-------|-------|
| Domain | `files.home-infra.net` |
| Target | `http://<filebrowser-lb-ip>:80` |
| SSL | Auto (Let's Encrypt) |
| Websockets | Enabled (upload progress) |

## Verification

After creating each resource, verify:

1. `curl -I https://watch.home-infra.net` — should return 200 or 302 (Jellyfin login)
2. `curl -I https://request.home-infra.net` — should return 200
3. `curl -I https://music.home-infra.net` — should return 200 or 302
4. `curl -I https://files.home-infra.net` — should return 200

## DNS Records (if not using wildcard)

If `*.home-infra.net` wildcard is not configured, add individual A records:

```
watch.home-infra.net    A    REDACTED_VPS_IP
request.home-infra.net  A    REDACTED_VPS_IP
music.home-infra.net    A    REDACTED_VPS_IP
files.home-infra.net    A    REDACTED_VPS_IP
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/media-pangolin-setup.md
git commit -m "Add Pangolin exposure runbook for media apps"
```

---

### Task 17: Backblaze B2 Backup Runbook

**Files:**
- Create: `docs/runbooks/media-backblaze-backup.md`

**Context:** Only irreplaceable personal media (music, photos, home videos) gets backed up off-site to Backblaze B2 via rclone. Downloaded movies/TV are replaceable and not backed up. Runs on cron from the Proxmox host directly.

- [ ] **Step 1: Create `docs/runbooks/media-backblaze-backup.md`**

```markdown
# Media Backup — Backblaze B2 with rclone

Off-site backup of irreplaceable personal media to Backblaze B2. Only `/data/media/music` and `/data/media/personal` are backed up — downloaded movies/TV can be re-acquired.

## Prerequisites

- Backblaze account (free tier: 10 GB, paid: $0.006/GB/month)
- rclone installed on `daytona` Proxmox host

## 1. Create Backblaze B2 Bucket

1. Log in to [Backblaze B2](https://secure.backblaze.com/b2_buckets.htm)
2. Create bucket:
   - Name: `homelab-media-backup` (must be globally unique — adjust as needed)
   - Type: Private
   - Encryption: Server-side (default)
   - Lifecycle: Keep all versions (for 30-day rollback)
3. Create Application Key:
   - App Keys > Add a New Application Key
   - Name: `homelab-rclone`
   - Bucket: select the bucket created above
   - Capabilities: Read and Write
   - **Save the keyID and applicationKey — shown only once**

## 2. Install and Configure rclone

```bash
# Install rclone on daytona
apt install -y rclone

# Configure remote
rclone config
# n) New remote
# name> b2-media-backup
# Storage> b2
# account> <keyID from step 1>
# key> <applicationKey from step 1>
# hard_delete> false
# Leave rest as defaults
```

Verify:

```bash
rclone lsd b2-media-backup:
```

## 3. Test Sync

```bash
# Dry run first
rclone sync /hdd-mirror/media-data/media/music b2-media-backup:homelab-media-backup/music --dry-run -v
rclone sync /hdd-mirror/media-data/media/personal b2-media-backup:homelab-media-backup/personal --dry-run -v

# Actual first sync (may take a while depending on data size)
rclone sync /hdd-mirror/media-data/media/music b2-media-backup:homelab-media-backup/music -v
rclone sync /hdd-mirror/media-data/media/personal b2-media-backup:homelab-media-backup/personal -v
```

## 4. Set Up Cron

```bash
cat > /etc/cron.d/rclone-media-backup << 'CRON'
# Daily rclone sync at 04:00 (after ZFS snapshot at 03:00)
0 4 * * * root rclone sync /hdd-mirror/media-data/media/music b2-media-backup:homelab-media-backup/music --log-file=/var/log/rclone-music.log --log-level INFO 2>&1
30 4 * * * root rclone sync /hdd-mirror/media-data/media/personal b2-media-backup:homelab-media-backup/personal --log-file=/var/log/rclone-personal.log --log-level INFO 2>&1
CRON
```

## 5. Verification

```bash
# List remote contents
rclone ls b2-media-backup:homelab-media-backup/music | head -20
rclone ls b2-media-backup:homelab-media-backup/personal | head -20

# Check size
rclone size b2-media-backup:homelab-media-backup

# Check cron logs
tail -50 /var/log/rclone-music.log
tail -50 /var/log/rclone-personal.log
```

## Cost Estimate

| Data | Size (est.) | Monthly Cost |
|------|-------------|-------------|
| Music | ~50 GB | $0.30 |
| Personal (photos/videos) | ~200 GB | $1.20 |
| **Total** | ~250 GB | **~$1.50/month** |

B2 egress is free for up to 3x stored data per month. Restore costs are effectively zero for disaster recovery scenarios.
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/media-backblaze-backup.md
git commit -m "Add Backblaze B2 rclone backup runbook for personal media"
```
