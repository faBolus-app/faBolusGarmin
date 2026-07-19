# PumpX2Garmin

A **standalone Garmin Connect IQ (Monkey C)** app that connects **directly** to a Tandem
t:slim X2 / Mobi pump over Bluetooth — no phone relay. Independent reimplementation of the
pump's protocol/auth/BLE (reverse-engineered by [pumpX2](https://github.com/jwoglom/pumpx2)).

> **Bench proof-of-concept only** — saline into a container on a scale, never on a body. Not
> affiliated with or endorsed by Tandem, jwoglom, or Garmin.

See **[HANDOFF.md](HANDOFF.md)** for the full brief and the two GO/NO-GO gates (CIQ BLE bonding to
the pump; EC-JPAKE on Monkey C).

## Status

Protocol + crypto + auth + message layers landed and **byte-exact vs the cliparser oracle**
(**31/31 unit tests pass** in the CIQ simulator). The BLE client compiles and boots a Gate A
smoke test, pending on-hardware validation.

This repo now holds **all the Garmin side**: the ControlX2 watch app (moved here from
`ControlX2iOS/garmin`, under `source/app/`) plus the direct-pump engine, which is wrapped in a
single **`PumpX2` namespace module** (`protocol` + `auth` + `messages` + `ble`) so its generic
names don't collide with the app's modules (`AppState`, `RemoteComm`, `Nav`, …). The app currently
uses its **phone-relay transport** (unchanged); the direct-BLE transport will be wired behind the
existing `RemoteComm`/`AppState` seam as a second transport — one Garmin app, no duplicated UX.
The Apple side (iPhone + Apple Watch, Swift/Xcode) stays in `ControlX2iOS`; the bridge contract is
`ControlX2iOS/schema/command.schema.json`.

- `source/app/` — the ControlX2 watch UI (glance/bolus/1-2-3 confirm/history/alerts, complication,
  `TrendArrow`, `AppState`, `Nav`). Entry: `ControlX2App`.
- `source/app/RemoteComm` — a transport **router** behind the existing `send(cmd)`/inbound seam:
  phone-relay (default) or **direct-to-pump** (`DirectTransport`, engine-backed). `DirectTransport`
  services the same command dicts (statusRead/bolusRequest/cancelBolus) locally over BLE — resume
  auth, status reads → `StatusFeed` dict, and the signed permission→initiate bolus flow — delivering
  replies in the identical schema so `AppState`/UI are unchanged. Direct mode is wired but dormant
  (`RemoteComm.enableDirect(secret)`); the lease/handoff policy that flips it comes with the
  phone-side coordination. The BLE session needs hardware; the pure `StatusFeed` mapping is unit-tested.
- `source/ble/GateAController` + `source/ui/GateAView` + `source/PumpX2GarminApp` — a Gate A
  bring-up harness (a second, non-default `AppBase`). To run it on hardware, temporarily set the
  manifest `entry` to `PumpX2GarminApp`.

- `source/protocol/` — `Bytes`, `Crc16` (CCITT/XModem), `Packetize` (framing + 24-byte HMAC-SHA1
  signed trailer + chunking), `Packet`/`PacketReassembler`, `Message`/`TransactionId`, `Ble` UUIDs,
  `ResponseParser` (CRC/length validation, signed-trailer stripping, opcode dispatch).
- `source/auth/` — `HmacSha1` (hand-rolled from CIQ SHA-1), `HmacSha256`, `Hkdf`, and
  `ResumeCoordinator` (on-watch JPAKE quick-pair rounds 3–4; derives the same `authKey` as the
  oracle's `jpake-server-resume`).
- `source/messages/` — request messages (`ApiVersion`, 20 empty-cargo status reads,
  `HistoryLog`, `Central`/`PumpChallenge`, `Jpake3/4`, signed bolus flow — the signed 1.0 U
  `InitiateBolusRequest` matches the oracle byte-for-byte) and response parsers (IOB, insulin,
  battery, CGM+trend, clock, basal, bolus status, signed bolus acks).
- `source/ble/` — `PumpBleClient` (registerProfile → scan → pairDevice → requestBond → subscribe →
  serialized writes; per-characteristic reassembly) + `GateAController`, driving the Gate A smoke
  test. **Compile-verified only; requires venu3s hardware + the bench pump to validate** (the
  simulator cannot exercise real BLE bonding/notifications).

Next: on-hardware Gate A, then the Milestone 0 handoff-resume probe (see the plan).

### Build & test

```
# release build (entry ControlX2App)
monkeyc -f monkey.jungle -o bin/PumpX2Garmin.prg -y developer_key.der -d venu3s -w
# unit tests (separate config with a minimal entry; simulator must be running: `connectiq`)
monkeyc -f test.jungle -o bin/PumpX2Garmin-test.prg -y developer_key.der -d venu3s --unit-test -w
monkeydo bin/PumpX2Garmin-test.prg venu3s -t
```

Golden oracle vectors live in `tests/golden_vectors.txt`; regenerate with `tools/gen_golden.sh`
(needs a JDK 14+ and the prebuilt `cliparser.jar`).

## Related
- [`PumpX2Kit`](https://github.com/zgranowitz/PumpX2Kit) — the Swift protocol/auth/BLE core
  (byte-exact vs the oracle); the primary reference to port from.
- [`ControlX2iOS`](https://github.com/zgranowitz/ControlX2iOS) — iOS host + the **phone-relay**
  Garmin remote; reuse its UI patterns (this project replaces the transport, not the UX).
