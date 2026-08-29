# Branch model, promotion, and the experimental gate

The canonical branch-governance document for all three code repos — **faBolus**, **TandemKit**, and
**faBolusGarmin** — lives in **faBolus** and governs this repo too:

**→ [`faBolus/BRANCHES.md`](https://github.com/faBolus-app/faBolus/blob/main/BRANCHES.md)**
&nbsp;(local sibling checkout: [`../faBolus/BRANCHES.md`](../faBolus/BRANCHES.md))

This repo deliberately keeps **no full copy** — a single source of truth avoids drift. This file is the
pointer. Read the canonical doc before opening a PR. In brief, as it applies here:

- **Two branches** — `main` (CI-green baseline) and `experimental` (§1.2: default-off /
  threshold-firing / not-verifiable-against-the-pump work). See §1.2 for what belongs on
  `experimental` and §1.4 for the promotion criteria. There is no `deprecated` BRANCH on any remote;
  the frozen pre-fix snapshot is the `deprecated/*` tag below.
- **Lockstep (§1.3).** faBolusGarmin moves in lockstep with the app: a Garmin `main` release accompanies
  every app `main` release and holds the **same quality bar**. Garmin work does not lag behind and does
  **not ship separately**.
- **Tags.** `safe-baseline/*` is the moving last-known-good pointer (the rollback target); `deprecated/*`
  is the immovable pre-round-3 snapshot. Per-release detail is in [`CHANGELOG.md`](CHANGELOG.md).
- **Branch-aware cross-repo CI.** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) checks the
  Monkey C mirror against faBolus's `schema/command.schema.json` at the **matching** branch (else
  `main`), logging the resolved ref **and its SHA** so a silent fallback can't green a mismatch.

See also [`CONTRIBUTING.md`](CONTRIBUTING.md) — it carries the §1.3/§1.4 cross-reference, the
lockstep clause, and the published device floor. [`AGENTS.md`](AGENTS.md) links here rather than
restating them.
