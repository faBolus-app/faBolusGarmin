# faBolusGarmin — remote-bolus security notes

The Garmin app is a **thin remote**: it relays a bolus request to the iPhone, which owns the pump and runs
every dose check. This note records the one open hardening item, proof of the confirmation gesture, and
the controls already in place around it.

## Open: application-level proof of the confirmation gesture

**Finding.** The watch sends a one-phase `bolus` message (`Wire.mc`, sent by `BolusFlow.send` after the
confirm), and the phone's remote host (faBolus `Packages/WatchLink`) delivers it. The payload is not
cryptographically bound to a human confirmation gesture, so a forged or replayed message from a
*compromised or replacement Connect IQ app* could in principle reach the host without the on-watch
confirm.

**Why it is not closed in code yet.** A watch app cannot produce a cryptographic proof that a *human*
performed the confirm: a compromised Connect IQ app could complete any client-side handshake (including a
two-phase token exchange) programmatically. The only control that truly proves a human gesture is a
**confirmation on the phone**, which changes the wrist remote's core value (dose without reaching for the
phone). Whether to force it, offer it as an option, or leave it off for Garmin is a **product decision**,
not a mechanical fix, so it is left to the owner.

**What already mitigates the sub-threats:**

| Sub-threat | Existing control |
|---|---|
| **Replay** of a captured request | The durable bolus ledger: a repeated `(peerId, requestId)` delivers at most once, even across an app relaunch, and a refused request keeps its refusal. A request older than 2 minutes by the phone's clock is refused. |
| **Wrong dose** / stale-settings dose | The phone recomputes the dose from the pump's latest values and refuses it if the watch's estimate differs by more than 0.10 U. Both calculators are tested against the same rows (`contract/bolus_oracle_fixtures.jsonl`), so the shown and delivered numbers agree. A correction-only request (zero carbs) goes through the same path. |
| **Mutated / malformed payload** | Every inbound field is type-, range- and finite-checked before it changes host or watch state. The schema is `additionalProperties: false`, the golden fixtures are what the phone's code writes, and a message of another protocol version is never read. |
| **Wrong device / cross-app** | Connect IQ delivers only to the paired companion app, and each personal beta has its own app id. |
| **Unauthorized surface** | Bolusing from the watch is off until the user turns it on in the phone app, a read-only switch blocks it, and an optional remote size limit caps each dose. The host refuses on its own state, whatever the watch sends. |

**Residual risk.** A *fully compromised* Connect IQ app on the paired watch could still submit a
within-tolerance, non-replayed, well-formed request that the host would honor without a human confirm.
That part needs the product decision above, or bench work on one of the options below.

**Options (pick one; test list below):**

1. **Phone confirmation for Garmin** (strongest): the phone shows the request and waits for a tap before
   delivering, gated by a user setting. It adds a phone tap per Garmin bolus.
2. **Two-phase token contract** (needs a protocol change; version 2 has no confirm token): watch `bolus`
   → host issues a short-lived single-use token bound to `{dose, device, expiry}` → after the confirm the
   watch sends a confirm carrying it → host verifies once. Closes replay, expiry, wrong dose, wrong
   device and mutation at the protocol layer, but not a compromised app that auto-confirms (hence
   option 1 for that threat).

**Tests required before trusting either path (bench):** bare request rejection, expired token, replay,
wrong dose, wrong device, mutated payload, reconnect mid-flow, and a successful confirmed request.

## Related controls

- A cancel is never gated, including in read-only mode.
- An outcome the phone doesn't know is shown as unknown, never as delivered or cancelled.
- Staleness is judged from the measurement time and the phone's windows, and kept across restarts; a
  value of unknown age is stale.
- On touch devices, one tap is handled once, never by two handlers.
