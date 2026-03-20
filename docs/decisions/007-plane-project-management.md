# ADR-007: Keep Plane for Project Management

**Status**: Accepted
**Date**: 2026-03-20
**Decision Makers**: Aaron

---

## Context

Plane's commercial version push (nag screens, upsell prompts) prompted an evaluation of open-source alternatives. The two strongest candidates — **Huly** and **Taiga** — were researched in depth alongside whether either could consolidate our docs platform (currently Outline).

## Alternatives Evaluated

### Huly

- **Strengths**: Modern Linear-like UX, all-in-one (PM + chat + video + docs), very active development (25K GitHub stars), EPL-2.0 license with zero feature gating on self-hosted, no per-seat pricing.
- **Blockers**:
  - **No Forgejo/Gitea integration** — only supports GitHub. Open feature request (#9743), no timeline.
  - **No official Helm chart** — community chart abandoned. Self-hosting requires CockroachDB + Redpanda + Elasticsearch operators.
  - **Resource-heavy** — 8-16 GB RAM vs Plane's ~4 GB.
  - **Docs feature is not Outline-quality** — no version history, no dedicated search, no standalone API, no templates.

### Taiga

- **Strengths**: Mature platform, excellent REST API (well-documented), multiple community MCP servers, MPL-2.0/AGPL-3.0 with no feature gating or commercial nag.
- **Blockers**:
  - **No Forgejo/Gitea integration** — supports GitHub/GitLab/Bitbucket only. Open request since 2021, unresolved.
  - **No official Helm chart** — community charts are unmaintained hobby projects.
  - **Maintenance mode** — core team shifted focus to Tenzu (ground-up rewrite by Biru cooperative). Classic Taiga has no clear roadmap.
  - **Wiki is flat pages only** — not a replacement for Outline.

### Outline (docs — separate evaluation)

Neither Huly nor Taiga can replace Outline. Huly's docs are collaborative notes within a PM tool (adequate for meeting notes, not a knowledge base). Taiga's wiki is a flat page structure with no hierarchy. Outline remains best-in-class for self-hosted wikis.

## Decision

**Keep Plane as our project management tool. Keep Outline as our documentation platform.**

The pain point (commercial nag) does not justify the migration cost and capability regression:

1. **Forgejo integration is a hard requirement** — neither alternative supports it, and we already work around Plane's lack of native Forgejo support via MCP tooling and manual links.
2. **Kubernetes deployment maturity** — Plane has an official Helm chart running in our cluster today. Both alternatives would require building and maintaining custom Helm charts.
3. **Existing MCP tooling** — our agent workflow is built on Plane's API. Migration means rebuilding all MCP integrations.
4. **No docs consolidation possible** — we'd still need Outline separately with either tool.

## Alternatives to Revisit

- **Huly**: If they ship Forgejo integration (#9743) and an official Helm chart, re-evaluate. Their licensing and feature set are genuinely strong.
- **Tenzu**: Taiga's successor. If it launches with modern deployment and Forgejo support, worth a look.

## Consequences

- Accept Plane's commercial nag as a minor annoyance.
- Pin to a known-good open-source version if the nag becomes more aggressive.
- Continue investing in Plane MCP tooling as our primary integration point.
- Deploy Outline as planned for documentation (separate concern, not coupled to this decision).
