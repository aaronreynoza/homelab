# MkDocs Documentation Site Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a self-hosted MkDocs Material documentation site as the first publicly exposed app via Pangolin at `docs.home-infra.net`.

**Architecture:** Multi-stage Docker build (MkDocs Material generates static HTML, Caddy serves it). Image pushed to Harbor (10.10.10.223), deployed via ArgoCD as plain K8s manifests in the `docs` namespace, exposed through Pangolin.

**Tech Stack:** MkDocs Material, Caddy 2, Docker, Harbor, ArgoCD, Cilium LB-IPAM, Pangolin

**Spec:** `docs/superpowers/specs/2026-03-13-mkdocs-docs-site-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `mkdocs.yml` (create) | MkDocs site config: theme, nav, extensions |
| `docs/index.md` (create) | Homepage content |
| `Caddyfile` (create) | Static file server config with security headers |
| `Dockerfile.docs` (create) | Multi-stage build: mkdocs → caddy |
| `core/manifests/apps/docs-site/deployment.yaml` (create) | K8s Deployment |
| `core/manifests/apps/docs-site/service.yaml` (create) | K8s Service (LoadBalancer) |
| `core/manifests/argocd/apps/docs-site.yaml` (create) | ArgoCD Application |

**Note:** The spec mentions `core/manifests/docs-site/` but the existing codebase pattern is `core/manifests/apps/<app-name>/` (see nginx-test). Follow the existing pattern.

**Note:** The spec mentions a separate `caddyfile-configmap.yaml`. Instead, bake the Caddyfile into the Docker image (simpler, one fewer moving part). A ConfigMap would only be needed if we wanted to change Caddy config without rebuilding the image, which isn't needed for a static site.

---

## Chunk 1: MkDocs Configuration and Content

### Task 1: Create MkDocs Configuration

**Files:**
- Create: `mkdocs.yml`

**Context:** This is the MkDocs Material configuration file. It goes in the repo root because `docs/` is already the content directory. The nav structure includes only public-safe content — no `internal-docs/`, `environments/`, `superpowers/`, or `issues/` directories.

- [ ] **Step 1: Create `mkdocs.yml`**

```yaml
site_name: Aaron's Homelab
site_description: Self-hosted infrastructure platform documentation
site_url: https://docs.home-infra.net

theme:
  name: material
  palette:
    - scheme: slate
      primary: indigo
      accent: indigo
      toggle:
        icon: material/brightness-7
        name: Light mode
    - scheme: default
      primary: indigo
      accent: indigo
      toggle:
        icon: material/brightness-4
        name: Dark mode
  features:
    - navigation.tabs
    - navigation.sections
    - navigation.expand
    - search.suggest
    - search.highlight
    - content.code.copy

markdown_extensions:
  - admonition
  - pymdownx.details
  - pymdownx.superfences
  - pymdownx.tabbed:
      alternate_style: true
  - pymdownx.highlight:
      anchor_linenums: true
  - tables
  - toc:
      permalink: true

nav:
  - Home: index.md
  - Architecture: architecture.md
  - Cloud Comparison: cloud-comparison.md
  - Setup:
      - Configuration: configuration.md
      - Infrastructure: 01-infrastructure.md
      - Deployment: 02-deployment.md
      - Ansible: 03-ansible.md
      - OPNSense: 04-opnsense.md
      - Security: 05-security.md
  - Decisions:
      - VLAN Architecture: decisions/001-vlan-architecture.md
      - TrueNAS Storage: decisions/002-truenas-storage.md
      - Pangolin + ControlD: decisions/003-pangolin-controld-architecture.md
      - SOPS Secrets: decisions/004-sops-secrets-management.md
  - Runbooks:
      - Initial Setup: runbooks/initial-setup.md
      - Terraform Backend: runbooks/terraform-backend-setup.md
      - Proxmox Recovery: runbooks/proxmox-recovery.md
      - VLAN Fix: runbooks/vlan-opnsense-fix.md
      - VLAN Routing: runbooks/mgmt-to-vlan-routing.md
      - Cluster Deployment: runbooks/prod-cluster-deployment.md
      - OPNSense Recovery: runbooks/opnsense-recovery-2026-02-11.md
  - Roadmap: roadmap.md
  - Changelog: CHANGELOG.md
```

- [ ] **Step 2: Verify the file references exist**

Run: `for f in index.md architecture.md cloud-comparison.md configuration.md 01-infrastructure.md 02-deployment.md 03-ansible.md 04-opnsense.md 05-security.md decisions/001-vlan-architecture.md decisions/002-truenas-storage.md decisions/003-pangolin-controld-architecture.md decisions/004-sops-secrets-management.md runbooks/initial-setup.md runbooks/terraform-backend-setup.md runbooks/proxmox-recovery.md runbooks/vlan-opnsense-fix.md runbooks/mgmt-to-vlan-routing.md runbooks/prod-cluster-deployment.md runbooks/opnsense-recovery-2026-02-11.md roadmap.md CHANGELOG.md; do [ -f "docs/$f" ] && echo "OK: $f" || echo "MISSING: $f"; done`

Expected: All files exist EXCEPT `index.md` (created in next task). If any other files are missing, check the `docs/` directory and adjust the nav accordingly.

---

### Task 2: Create Homepage

**Files:**
- Create: `docs/index.md`

**Context:** This is the landing page for the docs site. It should give a concise overview of the project — what it is, what's running, and how it's built. This is a portfolio piece, so it should be impressive but honest.

- [ ] **Step 1: Create `docs/index.md`**

```markdown
# Aaron's Homelab

A self-hosted infrastructure platform running on bare-metal hardware, designed to showcase DevOps and Platform Engineering skills while hosting production workloads.

## What's Running

| Service | Purpose |
|---------|---------|
| **Talos Linux** | Immutable Kubernetes OS |
| **Cilium** | CNI with L2 load balancing |
| **ArgoCD** | GitOps continuous delivery |
| **Longhorn** | Distributed block storage |
| **CloudNativePG** | PostgreSQL operator |
| **Forgejo** | Self-hosted Git (source of truth) |
| **Harbor** | Container registry |
| **Zitadel** | Identity & SSO |
| **Grafana + Prometheus** | Monitoring & alerting |
| **Loki + Tempo** | Logs & traces |
| **Velero** | Backup & disaster recovery |
| **Pangolin** | Public ingress via WireGuard tunnel |

## Architecture

Two fully isolated VLAN environments (prod + dev) on Proxmox, with OPNSense providing routing and firewall. All infrastructure is codified — Terraform for VMs, ArgoCD for Kubernetes workloads, SOPS for secrets.

See [Architecture](architecture.md) for diagrams and details.

## Cost

Running this entire platform costs ~$43/month. The cloud equivalent would be ~$253/month.
See [Cloud Comparison](cloud-comparison.md) for the breakdown.

## Source Code

This project is open source. The reusable infrastructure modules live in the public repository, while environment-specific configuration (credentials, IPs) is kept in a separate private repository.
```

- [ ] **Step 2: Commit MkDocs config and homepage**

```bash
git add mkdocs.yml docs/index.md
git commit -m "feat: add MkDocs Material configuration and homepage"
```

---

## Chunk 2: Docker Build (Caddyfile + Dockerfile)

### Task 3: Create Caddyfile

**Files:**
- Create: `Caddyfile`

**Context:** Caddy serves the static site on port 80 internally. TLS termination happens at Pangolin, not Caddy. The Caddyfile is baked into the Docker image.

- [ ] **Step 1: Create `Caddyfile`**

```
:80 {
    root * /srv
    file_server
    encode gzip
    try_files {path} {path}/ /index.html
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
    }
}
```

---

### Task 4: Create Dockerfile

**Files:**
- Create: `Dockerfile.docs`

**Context:** Multi-stage Docker build. Stage 1 installs MkDocs Material and builds static HTML from `docs/` + `mkdocs.yml`. Stage 2 copies the built site into a Caddy Alpine image. The result is a ~25MB image.

- [ ] **Step 1: Create `Dockerfile.docs`**

```dockerfile
# Build stage
FROM python:3.12-slim AS builder
RUN pip install --no-cache-dir mkdocs-material
WORKDIR /build
COPY mkdocs.yml .
COPY docs/ docs/
RUN mkdocs build

# Serve stage
FROM caddy:2-alpine
COPY --from=builder /build/site /srv
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80
```

- [ ] **Step 2: Test the Docker build locally**

Run: `docker build -f Dockerfile.docs -t docs-site:test .`

Expected: Build succeeds. The mkdocs build step should list all pages processed. If any markdown files have syntax issues, mkdocs will warn but still build.

- [ ] **Step 3: Test the container serves the site**

Run: `docker run --rm -d -p 8888:80 --name docs-test docs-site:test && sleep 2 && curl -s -o /dev/null -w "%{http_code}" http://localhost:8888 && docker stop docs-test`

Expected: HTTP 200. If you open `http://localhost:8888` in a browser, you should see the MkDocs Material site with the homepage content.

- [ ] **Step 4: Commit Caddyfile and Dockerfile**

```bash
git add Caddyfile Dockerfile.docs
git commit -m "feat: add Caddyfile and multi-stage Dockerfile for docs site"
```

---

## Chunk 3: Kubernetes Manifests and ArgoCD Application

### Task 5: Create K8s Deployment Manifest

**Files:**
- Create: `core/manifests/apps/docs-site/deployment.yaml`

**Context:** Follows the same pattern as `core/manifests/apps/nginx-test/deployment.yaml`. One replica, resource limits, liveness/readiness probes. The image tag will be updated each time the docs are rebuilt — initially `v1.0.0`.

Harbor is at `10.10.10.223`. Since Harbor is using HTTP (not HTTPS) internally, the K8s nodes need Harbor's IP in their container runtime's insecure registries list. If this isn't already configured, the image pull will fail with a TLS error. Check by examining the Talos machine config or by attempting to pull.

- [ ] **Step 1: Create the deployment manifest**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docs-site
  namespace: docs
  labels:
    app: docs-site
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docs-site
  template:
    metadata:
      labels:
        app: docs-site
    spec:
      containers:
        - name: caddy
          image: 10.10.10.223/platform/docs:v1.0.0
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 10
```

**Note:** We use `10.10.10.223` (Harbor's LB IP) as the registry address rather than `harbor.internal` because there's no internal DNS resolution for that hostname yet (ctrld on OPNSense is not configured). Once DNS is set up, this can be changed to `harbor.internal`.

**Note:** No `imagePullSecrets` is needed because Task 8 Step 1 creates the Harbor `platform` project with **Public** access level. If you accidentally create it as Private, pods will get `ImagePullBackOff` — go back to Harbor UI and change the project to Public.

---

### Task 6: Create K8s Service Manifest

**Files:**
- Create: `core/manifests/apps/docs-site/service.yaml`

**Context:** LoadBalancer service, same pattern as nginx-test. Cilium LB-IPAM will assign an IP from the 10.10.10.220-250 pool. No need to specify a specific IP — Cilium picks one automatically.

- [ ] **Step 1: Create the service manifest**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: docs-site
  namespace: docs
  labels:
    app: docs-site
spec:
  type: LoadBalancer
  selector:
    app: docs-site
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

---

### Task 7: Create ArgoCD Application

**Files:**
- Create: `core/manifests/argocd/apps/docs-site.yaml`

**Context:** This follows the app-of-apps pattern. The root ArgoCD app watches `core/manifests/argocd/apps/` and auto-discovers new Application manifests. This Application points to `core/manifests/apps/docs-site/` (the K8s manifests directory). The repoURL and targetRevision match the existing nginx-test Application.

- [ ] **Step 1: Create the ArgoCD Application manifest**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: docs-site
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
    path: core/manifests/apps/docs-site
  destination:
    server: https://kubernetes.default.svc
    namespace: docs
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

- [ ] **Step 2: Commit all K8s manifests**

```bash
git add core/manifests/apps/docs-site/deployment.yaml core/manifests/apps/docs-site/service.yaml core/manifests/argocd/apps/docs-site.yaml
git commit -m "feat: add K8s manifests and ArgoCD application for docs site"
```

---

## Chunk 4: Build, Push, and Deploy

### Task 8: Push Image to Harbor

**Context:** Harbor is running at `10.10.10.223`. You need to tag the image for Harbor's registry and push it. Harbor may require login first. The project `platform` may need to be created in Harbor's web UI if it doesn't exist (Harbor at `http://10.10.10.223`).

- [ ] **Step 1: Create the `platform` project in Harbor (if it doesn't exist)**

Open `http://10.10.10.223` in a browser. Log in with the admin credentials (from the `harbor-credentials` secret). Go to Projects → New Project → Name: `platform`, Access Level: Public. If the project already exists, skip this step.

- [ ] **Step 2: Configure Docker to trust Harbor's HTTP registry**

Since Harbor is running on HTTP (not HTTPS), Docker needs to know it's an insecure registry:

On macOS (Docker Desktop): Open Docker Desktop → Settings → Docker Engine → add `"insecure-registries": ["10.10.10.223"]` → Apply & Restart.

On Linux: Add `{"insecure-registries": ["10.10.10.223"]}` to `/etc/docker/daemon.json` and restart Docker.

- [ ] **Step 3: Log in to Harbor**

Run: `docker login 10.10.10.223`

Enter the Harbor admin username and password. First find the correct secret name, then retrieve the password:
```bash
# Find the Harbor credentials secret
kubectl get secrets -n harbor | grep -i credentials

# Retrieve the password (adjust secret name if different from harbor-credentials)
kubectl get secret harbor-credentials -n harbor -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Expected: `Login Succeeded`

- [ ] **Step 4: Build and tag for Harbor**

Run: `docker build -f Dockerfile.docs -t 10.10.10.223/platform/docs:v1.0.0 .`

Expected: Build succeeds.

- [ ] **Step 5: Push to Harbor**

Run: `docker push 10.10.10.223/platform/docs:v1.0.0`

Expected: Push succeeds, layers uploaded to Harbor. Verify the image appears in Harbor UI under the `platform` project.

- [ ] **Step 6: Verify Talos nodes can pull from Harbor**

The Talos machine config must list Harbor as an insecure registry. Check:

```bash
talosctl --talosconfig=./environments/prod/talosconfig get machineconfig -o yaml | grep -A5 "insecure"
```

If Harbor's IP is NOT listed, add it with a machine config patch. Apply to all nodes (control plane + workers):

```bash
# Create the patch file
cat > /tmp/harbor-registry-patch.yaml <<'PATCH'
machine:
  registries:
    mirrors:
      10.10.10.223:
        endpoints:
          - http://10.10.10.223
    config:
      10.10.10.223:
        tls:
          insecureSkipVerify: true
PATCH

# Apply to each node (replace IPs with actual node IPs)
talosctl --talosconfig=<path-to-talosconfig> patch mc -n <node-ip> --patch @/tmp/harbor-registry-patch.yaml
```

Also update the Terraform machine config template so future nodes get this config automatically (`core/terraform/modules/talos-cluster/` — look for `machine_configuration` or `config_patches`).

---

### Task 9: Push Code and Verify ArgoCD Deployment

- [ ] **Step 1: Push to remote**

Run: `git push`

Expected: ArgoCD root app detects the new `docs-site.yaml` Application manifest and creates the Application. The Application then syncs the K8s manifests from `core/manifests/apps/docs-site/`.

- [ ] **Step 2: Verify ArgoCD picks up the new app**

Run: `kubectl get application docs-site -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'`

Expected: Shows `docs-site` with Synced/Healthy (may take 1-3 minutes for ArgoCD to detect the new app). If ImagePullBackOff occurs, check Task 8 Step 6 (Talos insecure registry config).

- [ ] **Step 3: Verify the pod is running**

Run: `kubectl get pods -n docs`

Expected: `docs-site-<hash>` pod in `Running` state with `1/1` ready.

- [ ] **Step 4: Verify LoadBalancer IP assigned**

Run: `kubectl get svc docs-site -n docs`

Expected: Service has an `EXTERNAL-IP` from the 10.10.10.220-250 range.

- [ ] **Step 5: Smoke test the docs site**

Run: `curl -s -o /dev/null -w "%{http_code}" http://<EXTERNAL-IP>`

Expected: HTTP 200.

---

### Task 10: Configure Pangolin Public Access (Manual)

**Context:** This step is done in the Pangolin dashboard at the VPS. It creates a public resource that routes `docs.home-infra.net` traffic through the Newt WireGuard tunnel to the docs-site K8s service.

- [ ] **Step 1: Create Pangolin resource**

Open the Pangolin dashboard. Go to Resources → Public → Add Resource:
- **Domain:** `docs.home-infra.net`
- **Site:** Aaron Homelab
- **Target:** `http://<docs-site-EXTERNAL-IP>:80` (the Cilium LB IP from Task 9 Step 4)
- **SSL:** Enable (Let's Encrypt via Pangolin)
- **Auth:** None (public docs)

- [ ] **Step 2: Configure DNS (if needed)**

If `home-infra.net` doesn't already have a wildcard CNAME (`*.home-infra.net → pangolin-vps`), add a DNS record:
- Type: CNAME (or A record)
- Name: `docs`
- Value: Pangolin VPS IP (`207.246.115.3`) or its hostname

This is configured at the domain registrar or DNS provider (ControlD if DNS is managed there).

- [ ] **Step 3: Verify public access**

Run: `curl -s -o /dev/null -w "%{http_code}" https://docs.home-infra.net`

Expected: HTTP 200. The MkDocs Material site should be accessible from the public internet with valid TLS.

- [ ] **Step 4: Final commit — update CLAUDE.md**

Update the "Deployed Applications" section in CLAUDE.md to include the docs site. Commit:

```bash
git add CLAUDE.md
git commit -m "docs: add docs-site to deployed applications in CLAUDE.md"
git push
```
