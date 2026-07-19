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
(**28/28 unit tests pass** in the CIQ simulator). The BLE client compiles and boots a Gate A
smoke test, pending on-hardware validation.

The direct-pump engine (`protocol` + `auth` + `messages` + `ble`) is wrapped in a single
**`PumpX2` namespace module** so it can be pulled into the existing `ControlX2iOS/garmin` remote
app (via shared `sourcePath`) as a second, direct-BLE transport behind that app's
`RemoteComm`/`AppState` seam — one Garmin app, no duplicated UX. The Apple Watch app stays in
ControlX2iOS (it's Swift/watchOS). Consumers reference `PumpX2.PumpBleClient`,
`PumpX2.ResponseParser`, `PumpX2.ResumeCoordinator`, etc.

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
# release build
monkeyc -f monkey.jungle -o bin/PumpX2Garmin.prg -y developer_key.der -d venu3s -w
# unit tests (simulator must be running: `connectiq`)
monkeyc -f monkey.jungle -o bin/PumpX2Garmin-test.prg -y developer_key.der -d venu3s --unit-test -w
monkeydo bin/PumpX2Garmin-test.prg venu3s -t
```

Golden oracle vectors live in `tests/golden_vectors.txt`; regenerate with `tools/gen_golden.sh`
(needs a JDK 14+ and the prebuilt `cliparser.jar`).

## Related
- [`PumpX2Kit`](https://github.com/zgranowitz/PumpX2Kit) — the Swift protocol/auth/BLE core
  (byte-exact vs the oracle); the primary reference to port from.
- [`ControlX2iOS`](https://github.com/zgranowitz/ControlX2iOS) — iOS host + the **phone-relay**
  Garmin remote; reuse its UI patterns (this project replaces the transport, not the UX).
