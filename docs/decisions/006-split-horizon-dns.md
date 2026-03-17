# ADR-006: Split-Horizon DNS Implementation

**Status**: Accepted
**Date**: 2026-03-17
**Decision Makers**: Aaron

---

## Context

After migrating services from IP-based access (`http://10.10.10.225:8080`) to subdomain-based access via Pangolin (`https://zitadel.aaron.reynoza.org`), internal access is broken. All DNS queries for `*.aaron.reynoza.org` resolve to the Pangolin VPS public IP (`207.246.115.3`), causing traffic to hairpin: leave the home network, hit the VPS, then tunnel back in via WireGuard.

This creates three problems:

1. **gRPC doesn't work through Pangolin** — Pangolin's Traefik only proxies HTTP/HTTPS. The Zitadel Terraform provider uses gRPC and gets 404s.
2. **Unnecessary latency** — Internal traffic takes a round-trip through the internet.
3. **VPS dependency** — If the VPS is down, internal services become unreachable even though they're on the local network.

## Decision

Implement split-horizon DNS at two layers so internal DNS queries resolve to internal LB IPs directly.

## What is Split-Horizon DNS?

Split-horizon means the same domain resolves to different IPs depending on where the query comes from:

```
SAME DOMAIN: zitadel.aaron.reynoza.org

  From the internet  → 207.246.115.3  (Pangolin VPS — external path)
  From VLAN 10       → 10.10.10.225   (Cilium LB IP — direct)
  From a K8s pod     → 10.10.10.225   (Cilium LB IP — direct)
```

External users go through Pangolin (TLS + WireGuard tunnel). Internal users connect directly — no VPS, no tunnel, no internet round-trip.

## Architecture

### Without Split-Horizon (Broken)

```
Workstation / Pod
       |
       | DNS: zitadel.aaron.reynoza.org?
       v
  Cloudflare DNS
  → 207.246.115.3 (VPS)
       |
  Pangolin VPS (internet round-trip!)
       |
  WireGuard tunnel
       |
  Newt → K8s Service
```

Traffic hairpins through the internet. gRPC fails through Pangolin's HTTP proxy.

### With Split-Horizon (Fixed)

```
┌──────────────────────────────────────────────────┐
│  EXTERNAL USER                                    │
│       |                                           │
│  Cloudflare DNS → 207.246.115.3 (Pangolin VPS)  │
│       |                                           │
│  Pangolin → WireGuard → Newt → K8s Service       │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│  INTERNAL (VLAN 10)                               │
│                                                   │
│  Workstation          K8s Pod                     │
│       |                    |                      │
│  ctrld (OPNSense)    CoreDNS (cluster)           │
│  → 10.10.10.225      → 10.10.10.225             │
│       |                    |                      │
│       └────────┬───────────┘                      │
│                |                                  │
│         K8s Service (direct!)                     │
└──────────────────────────────────────────────────┘
```

## Two Layers

Split-horizon requires two DNS layers because K8s pods and network devices use different DNS servers.

### Layer 1: CoreDNS Custom Zone (In-Cluster)

**What:** Add a `hosts` block to the cluster's CoreDNS configuration.
**Who it serves:** All K8s pods (Grafana, ArgoCD, Forgejo, etc.)
**Why:** Pods use CoreDNS for DNS. Without this, pod-to-pod OIDC flows (Grafana validating tokens against Zitadel) hairpin through the internet.

```
Pod DNS query: zitadel.aaron.reynoza.org?
       |
   CoreDNS
       |
       ├─ Match *.aaron.reynoza.org? → YES → return 10.10.10.225
       |
       └─ No match? → forward to OPNSense → Cloudflare (normal)
```

### Layer 2: ControlD/ctrld on OPNSense (Network-Level)

**What:** Configure domain overrides in ctrld so VLAN 10 queries resolve internally.
**Who it serves:** Workstation, management VM, any device on VLAN 10.
**Why:** The Terraform provider runs from the workstation and needs gRPC access to Zitadel. Browsers need direct access for local development.

```
Workstation DNS query: zitadel.aaron.reynoza.org?
       |
   OPNSense (ctrld)
       |
       ├─ Match *.aaron.reynoza.org? → YES → return 10.10.10.225
       |
       └─ No match? → forward to ControlD/Cloudflare (normal)
```

### Why Both Are Needed

| Layer | Covers | Does Not Cover |
|-------|--------|----------------|
| CoreDNS (cluster) | Pods: Grafana→Zitadel, ArgoCD→Forgejo | Workstation, mgmt VM |
| ctrld (OPNSense) | Workstation, mgmt VM, local devices | K8s pods |

## DNS Record Mapping

| Subdomain | Internal LB IP | Service |
|-----------|---------------|---------|
| `argocd.aaron.reynoza.org` | 10.10.10.221 | ArgoCD |
| `forgejo.aaron.reynoza.org` | 10.10.10.222 | Forgejo |
| `harbor.aaron.reynoza.org` | 10.10.10.223 | Harbor |
| `grafana.aaron.reynoza.org` | 10.10.10.224 | Grafana |
| `zitadel.aaron.reynoza.org` | 10.10.10.225 | Zitadel |
| `chat.aaron.reynoza.org` | 10.10.10.227 | Open WebUI |

## External Access (Outside the Network)

Split-horizon only affects internal DNS resolution. **External access works without it.**

When you're outside (e.g., at a park), all traffic goes through Pangolin via HTTPS — including OAuth/OIDC login flows. This works because OIDC is pure HTTPS (redirects + API calls), which Pangolin proxies fine.

| Protocol | Used By | Through Pangolin? |
|----------|---------|-------------------|
| **HTTPS** | Browser login, OIDC flows, all user interaction | Yes — works externally and internally |
| **gRPC** | Terraform Zitadel provider only (admin tooling) | No — requires direct connection (split-horizon or VPN) |

gRPC is an implementation detail of the Terraform provider. Users never encounter it. The split-horizon fix is about:
1. **Performance** — internal traffic stays local (no VPS round-trip)
2. **Terraform** — gRPC needs direct connection to Zitadel
3. **Resilience** — internal operations don't depend on VPS availability

## TLS Consideration

With split-horizon, internal traffic reaches services via plain HTTP (LB IPs don't have TLS certs). This is acceptable:
- Traffic never leaves the local network (VLAN 10)
- External traffic still gets TLS via Pangolin

For internal HTTPS, deploy cert-manager with Cloudflare DNS-01 (Option B in ADR-005). This is a future enhancement, not a blocker.

## Implementation

### CoreDNS (managed via Talos machine config or Helm)

Add to the CoreDNS Corefile:

```
aaron.reynoza.org {
    hosts {
        10.10.10.221 argocd.aaron.reynoza.org
        10.10.10.222 forgejo.aaron.reynoza.org
        10.10.10.223 harbor.aaron.reynoza.org
        10.10.10.224 grafana.aaron.reynoza.org
        10.10.10.225 zitadel.aaron.reynoza.org
        10.10.10.227 chat.aaron.reynoza.org
        fallthrough
    }
}
```

### ControlD/ctrld (on OPNSense)

Configure domain overrides in the ControlD dashboard or ctrld config file. Each `*.aaron.reynoza.org` subdomain maps to its internal LB IP.

## Relationship to Other ADRs

| ADR | Relationship |
|-----|-------------|
| [ADR-003: Pangolin + ControlD](003-pangolin-controld-architecture.md) | Implements step 5 (ctrld on OPNSense) and step 7 (split-horizon) |
| [ADR-005: DNS/TLS/Service Exposure](005-dns-tls-service-exposure.md) | Implements step 4 (ControlD split-horizon) |

---

**Last Updated:** 2026-03-17
