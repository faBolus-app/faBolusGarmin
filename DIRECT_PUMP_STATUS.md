# Direct-to-Pump on Garmin — Status & Handoff (paused)

This repo currently ships the **faBolus Garmin watch app** as a **phone-relay remote** (talks to
the iPhone host over the Connect IQ mobile SDK; the phone owns the pump connection via PumpX2Kit).
A parallel effort to make the watch talk to the pump **directly over BLE** is **paused** — the code
lives under `direct-pump/` and this document explains what works, what's blocked, and how to resume.

Bench proof-of-concept only (saline, on a scale, never on a body).

## TL;DR — why it's paused
Direct watch→pump control is blocked by the pump + platform, not by our code:
- The **t:slim X2 allows one BLE controller at a time**, and (confirmed on the bench) **generating a
  pairing code for a new device invalidates the old** — i.e. switching between phone and watch
  requires a **full re-pair each time**. There is no "both paired, one active" mode, and the
  shared-secret **resume** shortcut cannot bootstrap a watch that has never paired.
- A first-time pairing requires **full EC-JPAKE** (secp256r1, 6-digit code). **Garmin Monkey C has
  no EC-JPAKE and no EC point arithmetic** (`Toybox.Cryptography` gives SHA-1/256, HMAC-SHA256,
  AES, a whole-keypair secp256r1 + one ECDH shared secret — not enough).
- So the only path to direct control is **implementing EC-JPAKE in pure Monkey C**, whose
  **on-watch performance is unproven** (256-bit modular math, interpreted, ~tens of thousands of
  ops per handshake). That's the open go/no-go.

## What was proven to WORK (on the venu3s hardware)
- The venu3s **can register a BLE profile and scan as a central**, and it **found + matched the
  t:slim X2 and began pairing** (Gate A's hard parts pass).
- The full protocol/crypto **port is byte-exact vs jwoglom's `cliparser` oracle** (32 unit tests):
  framing (`Packetize` + CRC-16 + chunking), the 24-byte HMAC-SHA1 signed trailer, HKDF/HMAC-SHA256,
  the JPAKE **resume** rounds 3–4 (derive the same `authKey` as `jpake-server-resume`), all request
  messages incl. the signed 1.0 U `InitiateBolusRequest`, and response parsing.

## What's blocked / not done
- **Full EC-JPAKE pairing on-watch** (rounds 1–2 + Schnorr ZKPs + derive) — not implemented; needs
  pure-Monkey C secp256r1. This is the crux.
- Live read/bolus over direct BLE — never exercised end-to-end (couldn't get past pairing).

## Bench test that settled it
With the phone disconnected and the pump put into add-device/pairing mode, the watch **found
`tslim X2…`, matched, and started pairing** — but the pump then expects a fresh full JPAKE
handshake (a 6-digit code), which the watch can't perform. Scanning while the pump was NOT in
pairing mode showed only unrelated BLE devices (the pump doesn't advertise to a new central while
phone-connected). See `HANDOFF_TEST.md` for the procedure.

## Where the code is
- `direct-pump/engine/` — the **validated port** (PumpX2 namespace): `protocol` (Bytes, Crc16,
  Packetize, Packet/reassembler, Message, ResponseParser, Ble UUIDs), `auth` (HmacSha1, HmacSha256,
  Hkdf, ResumeCoordinator), `messages` (requests + responses), `ble` (PumpBleClient + GateAController).
  Compiled + exercised by `tests/` and `probe/`.
- `direct-pump/transport/` — `DirectTransport` (maps the app's command dicts to engine calls;
  status reads, signed bolus with polling, dismiss) + `StatusFeed`. **Coupled to the router version
  of `RemoteComm`; needs rewiring** to be used again.
- `direct-pump/harness/` — the Gate A / debug UI used during bring-up (`FaBolusGarminApp`,
  `GateAView`, `DirectDebugView`/`Delegate`). Archived; not compiled.
- `probe/` — a standalone app that drives bond → JPAKE **resume** with a pasted secret (built via
  `probe.jungle`); used for the Milestone 0 handoff probe.
- `tests/` — oracle-parity + resume unit tests (`test.jungle`, entry `TestEntryApp`).
- `tools/gen_golden.sh` + `tests/golden_vectors.txt` — regenerate the oracle vectors (needs a
  JDK 14+ and the prebuilt `cliparser.jar` in the PumpX2Kit oracle submodule).

## How to resume (recommended order)
1. **Feasibility spike (go/no-go):** implement an *optimized* 256-bit modmul over the P-256 prime
   — schoolbook multiply + **NIST P-256 fast reduction** (not bit-serial) — validate against the
   P-256 vectors, and **time it in the simulator** to estimate a full-handshake cost on the venu3s.
   If it's minutes, direct control is likely impractical; if a few seconds, proceed.
2. **Curve + protocol:** secp256r1 point add/double/scalar-mul → EC-JPAKE rounds 1–2 + Schnorr ZKPs
   + derive, matching mbedTLS/BouncyCastle wire format; validate the derived secret against the
   oracle's `jpake-server`.
3. **Wire it up:** rewire `DirectTransport` behind a transport router in the app; add a **6-digit
   code entry UI** on the venu3s; pump in add-device mode → full JPAKE → then the existing resume
   path for later reconnects (though the t:slim X2 will require a fresh code on each phone↔watch
   switch, so "seamless" isn't achievable — it's a deliberate re-pair).

## Build
- Shipping watch app: `monkeyc -f monkey.jungle -o bin/faBolus.iq -y <key> -e -r -w`
- Engine unit tests: `monkeyc -f test.jungle ... --unit-test` then `monkeydo ... venu3s -t`
- Resume probe: `monkeyc -f probe.jungle ...`

The iOS side (faBolus) is the phone host + Apple Watch app; the bridge contract is
`faBolus/schema/command.schema.json`.
