# PumpX2Garmin

A **standalone Garmin Connect IQ (Monkey C)** app that connects **directly** to a Tandem
t:slim X2 / Mobi pump over Bluetooth — no phone relay. Independent reimplementation of the
pump's protocol/auth/BLE (reverse-engineered by [pumpX2](https://github.com/jwoglom/pumpx2)).

> **Bench proof-of-concept only** — saline into a container on a scale, never on a body. Not
> affiliated with or endorsed by Tandem, jwoglom, or Garmin.

See **[HANDOFF.md](HANDOFF.md)** for the full brief and the two GO/NO-GO gates (CIQ BLE bonding to
the pump; EC-JPAKE on Monkey C).

## Status

Protocol + crypto foundation landed and **byte-exact vs the cliparser oracle** (15/15 unit tests
pass in the CIQ simulator):

- `source/protocol/` — `Bytes`, `Crc16` (CCITT/XModem), `Packetize` (framing + 24-byte HMAC-SHA1
  signed trailer + chunking), `Packet`/`PacketReassembler`, `Message`/`TransactionId`, `Ble` UUIDs.
- `source/auth/` — `HmacSha1` (hand-rolled from CIQ SHA-1), `HmacSha256`, `Hkdf`.
- `source/messages/` — request messages: `ApiVersionRequest`, 20 empty-cargo status reads,
  `HistoryLogRequest`, `Central`/`PumpChallengeRequest`, `Jpake3SessionKey`/`Jpake4KeyConfirmation`,
  and the signed bolus flow (`BolusPermission`/`InitiateBolus`/`CancelBolus`/`BolusPermissionRelease`)
  — the signed 1.0 U `InitiateBolusRequest` matches the oracle byte-for-byte.

Not yet built: response parsing + `ResponseParser`, the on-watch JPAKE resume coordinator, and the
BLE client (Gate A). See the plan and task list.

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
