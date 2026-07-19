# PumpX2Garmin

A **standalone Garmin Connect IQ (Monkey C)** app that connects **directly** to a Tandem
t:slim X2 / Mobi pump over Bluetooth — no phone relay. Independent reimplementation of the
pump's protocol/auth/BLE (reverse-engineered by [pumpX2](https://github.com/jwoglom/pumpx2)).

> **Bench proof-of-concept only** — saline into a container on a scale, never on a body. Not
> affiliated with or endorsed by Tandem, jwoglom, or Garmin.

**Status: not started.** See **[HANDOFF.md](HANDOFF.md)** for the full brief — start with the
two GO/NO-GO gates (CIQ BLE bonding to the pump; EC-JPAKE on Monkey C) before building anything.

## Related
- [`PumpX2Kit`](https://github.com/zgranowitz/PumpX2Kit) — the Swift protocol/auth/BLE core
  (byte-exact vs the oracle); the primary reference to port from.
- [`ControlX2iOS`](https://github.com/zgranowitz/ControlX2iOS) — iOS host + the **phone-relay**
  Garmin remote; reuse its UI patterns (this project replaces the transport, not the UX).
