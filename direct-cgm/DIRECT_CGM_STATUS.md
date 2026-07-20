# Direct-CGM (Dexcom G7 / ONE+) — status: PAUSED / compile-verified only

This mirrors the paused `direct-pump/` work: an independent, **read-only** watch BLE path that lets
the Garmin remote read a Dexcom G7/ONE+ **directly** as a failover when the iPhone is out of range.
It is **not part of the shipping build** (`monkey.jungle` compiles only `source/app`).

## What's here
- `engine/G7Message.mc` — G7 glucose (0x4e) + backfill decoders, ported from the vendored Swift
  `G7SensorKit` (LoopKit, MIT). Passive: parses the broadcast the official Dexcom app authenticated;
  we never send auth.
- `engine/G7BleClient.mc` — `Toybox.BluetoothLowEnergy` client: registerProfile → scan (name
  `DXCM…`) → pairDevice → subscribe to the control + backfill + communication notifications → decode.
  **Never** writes the authentication/control value characteristics, so it can't disconnect the
  official app.
- `harness/CgmProbeApp.mc` + `harness/CgmProbeView.mc` — a standalone probe app that shows the last
  direct-BLE glucose, for the on-device test.

## Build (compile-verify)
```
monkeyc -f direct-cgm.jungle -o bin/faBolusGarmin-cgm.prg -y developer_key.der -d venu3s -w
```

## Why paused
CIQ BLE can't be validated in the simulator, and this needs a live G7 to confirm the passive link
works alongside the official app (multi-connection). Once verified on-device, wire it behind the same
seam that feeds `AppState.glucose` (see `source/app/AppState.mc`), started only while the phone is
unreachable, so the watch keeps showing glucose without the phone — matching the Apple Watch failover
in `Shared/DexcomG7BLESource.swift`.
