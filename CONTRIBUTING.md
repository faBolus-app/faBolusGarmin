# Contributing to faBolusGarmin

faBolusGarmin is a **host- and pump-agnostic Garmin remote**. It speaks the JSON contract in
[`faBolus`](https://github.com/faBolus-app/faBolus)'s `schema/command.schema.json`; any host that
implements that contract can drive it. Contributions are welcome by **PR, not fork**. All work is
**bench/experimental only** (saline into a container on a scale, never on a body).

## Keep it host-agnostic
- The watch is a thin remote. Everything it sends/receives is the shared contract
  (`statusRead` / `bolusRequest` / `cancelBolus` / `dismissAlert` + the status payload). Don't bake
  assumptions about a specific pump or host into the phone-relay path.
- `RemoteComm` is the one seam for transports — add transports there and leave the UI / `AppState`
  untouched.

## The contract mirror (don't let it drift)
The source of truth is `faBolus/schema/command.schema.json`, mirrored in Swift (`RemoteCommand`) and
here in Monkey C (`RemoteCommand.mc`). If you change the contract:
1. Update the schema and bump its `version`, plus the Swift mirror (in faBolus).
2. Update the Monkey C mirror to match.
3. Prefer additive, optional fields so older remotes keep working.

## Safety
- Never weaken the interlocks: the 1-2-3 / hold confirmation on the watch is a **second** factor; the
  host still enforces its own confirmation + max-bolus clamp. Dosing changes get extra review.
- The direct-to-pump engine (`direct-pump/`) is the most safety-critical code — it signs and sends
  real pump commands — and must stay **byte-exact vs the pumpX2 `cliparser` oracle**.

## Before a PR
- Build the app:
  `monkeyc -f monkey.jungle -o bin/faBolusGarmin.prg -y developer_key.der -d venu3s -w`.
- Run the unit tests in the CIQ simulator (README → "Build & test"); the oracle golden vectors must
  pass.
- Note anything only compiled vs. bench-tested on hardware.
