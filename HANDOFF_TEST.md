# Milestone 0 — Handoff-Resume Probe (bench procedure)

**Question this answers:** can a *second* BLE central (the venu3s) establish its own fresh bond to
the pump and complete **JPAKE resume** (rounds 3–4) using a **derived secret shared from the
iPhone** — *without* a new 6-digit code — so the watch can take over directly when the phone is
away? The answer decides whether the seamless shared-key handoff is possible, or whether the
achievable model is "one host at a time, switching requires a full re-pair."

> ⚠️ **Bench proof-of-concept only.** Use a dedicated **test pump dispensing saline into a
> container on a scale — never on a body.** The derived secret is long-term pairing material;
> treat it like a credential and delete the copy afterward.

The **Direct (debug)** screen (last in the watch app's swipe rotation) subsumes **Gate A**: its
status line goes `registering profile → scanning → pairing → connected → bonding → bonded →
subscribing → ready → resuming (rounds 3-4)`, which *is* the Gate A bond+subscribe+notify test,
before it attempts resume.

---

## Preferred flow — through the shipped app (no sideloading)

Use this when you can push a normal Connect IQ update to the watch but can't sideload from a Mac.
The direct-to-pump path is built into the real faBolus app; the secret is shared from the phone
over the Connect IQ bridge.

### Prerequisites
- The bench pump (Mobi / t:slim X2 v7.7+, 6-digit JPAKE), **not currently bonded to any other
  device**.
- The updated **faBolus Garmin app** on the venu3s (built from `monkey.jungle`, includes the
  Direct debug screen) and the updated **iPhone app** (includes "Send pump key to Garmin").

### Steps
1. **Pair the pump from the iPhone** (faBolus → Connect → 6-digit code); confirm it reads status.
2. **Share the key to the watch**: faBolus → **Settings → Pump → "Send pump key to Garmin
   (debug)"**. (Requires the Garmin remote to have been set up once via "Set up Garmin remote".)
   The watch stores the derived secret.
3. **Free the single bond**: in faBolus Disconnect, then **iOS Settings → Bluetooth → forget the
   pump**. If the Mobi needs pairing-mode entry (charging pad) to accept a new central, note that —
   it's part of the result.
4. **On the watch**, open the faBolus app and **swipe up past the last screen to "Direct
   (debug)"**, then **tap** it. Watch the status line.

---

## Alternative flow — standalone probe (if you can sideload)

The `probe/` app (built via `probe.jungle`) does the same thing with the secret pasted into a
constant. Read the secret via faBolus → Settings → Pump → **"Copy pairing secret (debug)"**, paste
into `probe/ProbeController.mc` (`DERIVED_SECRET_HEX`), build
(`monkeyc -f probe.jungle -o bin/faBolusGarmin-probe.prg -y developer_key.der -d venu3s -w`), sideload,
free the phone bond (step 3 above), then launch the probe.

## Interpreting the result

| What you see | Meaning | Consequence |
|---|---|---|
| **`HANDOFF PASS`** (detail: `authed read op=37`) | Fresh watch bond **+** resume with the shared secret **+** an authenticated read all succeeded. | ✅ **Shared-key sequential handoff is viable.** Build the key-share + lease (task #9); direct failover can be (near-)seamless. |
| Reaches **`resuming (rounds 3-4)`** then **`RESUME FAILED`** | Watch bonded + subscribed, but the pump rejected the resume handshake. | ❌ Pump won't resume for a different central with a shared secret. Fall back to **manual role-switch (full re-pair per device)** or standalone. |
| Stuck at `scanning`/`pairing`/`bonded`/`subscribing`, or the **pump shows a new 6-digit code / pairing prompt** | The pump forced a *fresh full pairing* at the bond layer (bootstrap, not resume). | ❌ No shared-key handoff. A new bond ⇒ new code ⇒ rotated secret. |
| **`ERROR`** with a detail line | BLE-level failure (`registerProfile`, `pairDevice`, bond). | Gate A concern — capture the detail; may indicate CIQ can't bond as a second central at all. |

**Also record either way:**
- Did bonding require **physical pairing-mode entry** on the Mobi (charging pad / button)? If so,
  full automation is capped regardless of the crypto result.
- Whether the pump issued a **new 6-digit code** during the attempt (⇒ the secret rotated; the phone
  will need to re-pair afterward).

## After the test
- Re-pair the phone to the pump if the secret rotated (faBolus → Re-pair with new code).
- Delete the copied secret from your Mac/clipboard.
- The probe is a throwaway build; the shipping app is built from `monkey.jungle`.

## Reporting back
Tell me the status-line outcome + the two "record either way" facts. That selects the branch in the
plan: PASS → wire the key-share + single-writer lease (task #9); FAIL → manual role-switch or
standalone, and we adjust the transport router accordingly.
