# Milestone 0 — Handoff-Resume Probe (bench procedure)

**Question this answers:** can a *second* BLE central (the venu3s) establish its own fresh bond to
the pump and complete **JPAKE resume** (rounds 3–4) using a **derived secret shared from the
iPhone** — *without* a new 6-digit code — so the watch can take over directly when the phone is
away? The answer decides whether the seamless shared-key handoff is possible, or whether the
achievable model is "one host at a time, switching requires a full re-pair."

> ⚠️ **Bench proof-of-concept only.** Use a dedicated **test pump dispensing saline into a
> container on a scale — never on a body.** The derived secret is long-term pairing material;
> treat it like a credential and delete the copy afterward.

The probe app (`probe/`, built via `probe.jungle`) subsumes **Gate A**: its lifecycle line goes
`registering profile → scanning → pairing → connected → bonding → bonded → subscribing → ready`,
which *is* the Gate A bond+subscribe+notify test, before it attempts resume.

---

## Prerequisites
- venu3s in developer mode (sideload enabled), Connect IQ SDK 9.2.0, and `developer_key.der` in the
  repo root (already present on the build machine).
- The bench pump (Mobi / t:slim X2 v7.7+, 6-digit JPAKE), **not currently bonded to any other
  device**.
- iPhone with the ControlX2 app (this build includes the debug "Copy pairing secret" affordance).

## Steps

**1. Pair the pump from the iPhone (produces the derived secret).**
In ControlX2: Connect → enter the pump's 6-digit code → confirm it connects and shows a reading.

**2. Copy the derived secret off the phone.**
ControlX2 → **Settings → Pump → "Copy pairing secret (debug)"**. AirDrop/paste the hex (64 hex
chars) to your Mac.

**3. Build + sideload the probe with that secret.**
Paste the hex into `probe/ProbeController.mc` → `const DERIVED_SECRET_HEX = "…";`, then:
```
monkeyc -f probe.jungle -o bin/PumpX2Garmin-probe.prg -y developer_key.der -d venu3s -w
```
Sideload `bin/PumpX2Garmin-probe.prg` to the venu3s (Connect IQ store beta / Garmin Express /
copy to `GARMIN/APPS/`). Do **not** launch it yet.

**4. Release the pump from the phone (free the single bond).**
In ControlX2: Disconnect. Then **iOS Settings → Bluetooth → forget the pump** (drops the OS-level
bond). If the Mobi needs to be put into pairing mode to accept a new central (e.g. on its charging
pad), note that — **it's part of the result** (see below).

**5. Run the probe on the watch and read the status line.**
Launch the probe app on the venu3s and watch the top status text.

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
- Re-pair the phone to the pump if the secret rotated (ControlX2 → Re-pair with new code).
- Delete the copied secret from your Mac/clipboard.
- The probe is a throwaway build; the shipping app is built from `monkey.jungle`.

## Reporting back
Tell me the status-line outcome + the two "record either way" facts. That selects the branch in the
plan: PASS → wire the key-share + single-writer lease (task #9); FAIL → manual role-switch or
standalone, and we adjust the transport router accordingly.
