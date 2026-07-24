# faBolusGarmin — remote-bolus security notes

The Garmin app is a **thin remote**: it relays a bolus request to the iPhone host, which owns the pump
and runs every safety interlock. This note records the one open hardening item (GA-01) and the controls
already in place around it.

## GA-01 — application-level proof of the confirmation gesture (open, bench/product-gated)

**Finding.** The watch sends a one-phase `bolusRequest` (`RemoteComm.mc`, `HoldView.confirmDeliver`),
and `GarminRemoteBridge` on the phone delivers it. The payload is not cryptographically bound to a
human confirmation gesture, so a forged or replayed message from a *compromised or replacement Connect
IQ app* could in principle reach the host without the on-watch hold.

**Why it is not closed in code yet.** A watch app cannot produce a cryptographic proof that a *human*
performed the hold — a compromised CIQ app could complete any client-side handshake (including a
two-phase token exchange) programmatically. The only control that truly proves a human gesture is
**phone-side confirmation**, which changes the wrist remote's core value (dose without reaching for the
phone). Whether to force, offer-as-opt-in, or leave phone-confirm off for Garmin is a **product
decision**, not a mechanical fix — so it is left to the owner rather than changed unilaterally.

**What already mitigates the sub-threats** (the individually-testable parts of the finding):

| Sub-threat | Existing control |
|---|---|
| **Replay** of a captured request | Durable idempotency ledger (FB-03): a repeated `(peerId, requestId)` is a no-op; a settled id never re-delivers, even across app relaunch. |
| **Wrong dose** / stale-settings dose | Host recomputes the authoritative dose and rejects if the watch estimate diverges > 0.10 U (C-06); component rounding now matches the oracle (GA-04), so the shown and delivered numbers agree. |
| **Mutated / malformed payload** | Inbound validation (GA-09): every field is type/range/finite-checked and enum-validated before it mutates host or watch state; the schema is `additionalProperties:false` and payloads are validated against it in CI (GA-07). |
| **Wrong device / cross-app** | Connect IQ delivers only to the specific paired companion app; each tester build uses a per-person app id. |
| **Unauthorized surface** | Child-mode gating (A1) and per-device read-only (the host refuses a bolus from a read-only/locked peer regardless of what the watch sends). |

**Residual risk.** A *fully compromised* CIQ app on the paired watch could still submit a
within-tolerance, non-replayed, well-formed request that the host would honor without a human hold. This
is the part that needs either the product decision above or bench validation.

**Bench/implementation options (pick one; test list below):**

1. **Phone confirmation for Garmin** (strongest): route Garmin requests through the host's existing
   `presentRemoteBolus` → on-phone `confirmRemoteBolus` interlock (as other remotes can), gated by a
   user setting. Reuses proven code; adds a phone tap per Garmin bolus.
2. **Two-phase token contract** (schema already supports it — `bolusConfirm` + short-lived
   single-use `confirmToken`): watch `bolusRequest` → host issues a token bound to `{dose, device,
   expiry}` → after the hold the watch sends `bolusConfirm{confirmToken}` → host verifies once. Closes
   replay/expiry/wrong-dose/wrong-device/mutation at the protocol layer (but not a compromised app that
   auto-confirms — hence option 1 for that threat).

**Tests required before trusting either path (bench):** bare request rejection, expired token, replay,
wrong dose, wrong device, mutated payload, reconnect mid-flow, and a successful confirmed request.

## Related closed items

- **GA-02** cancel works in read-only. **GA-03** no fabricated delivered/cancelled outcome (explicit
  `unknown`). **GA-04** oracle component-rounding parity. **GA-05** correction-only (zero-carb) requests
  route through the host carb path. **GA-06** touch devices suppress double-routing. **GA-07** schema
  screens/status + full-payload validation. **GA-08** staleness persisted/honored. **GA-09** inbound
  validation. See the commit history and `faBolus-internal/REMEDIATION.md`.
