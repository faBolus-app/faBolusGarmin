<!--
faBolusGarmin is the experimental Garmin remote for faBolus, an insulin-pump app. The delivery
disposition is NO-GO for real insulin delivery; keep it that way unless changing it is the explicit
subject of this PR. The watch never doses on its own — it requests, the phone host confirms + clamps.
Fill in what applies; delete what doesn't. See CONTRIBUTING.md, AGENTS.md, and BRANCHES.md.
-->

## What & why

<!-- One or two sentences. What changes, and the problem it solves. -->

## Branch target

- [ ] `main` — meets every §1.4 promotion criterion (see BRANCHES.md → faBolus/BRANCHES.md)
- [ ] `experimental` — fires on a threshold / automates a decision / produces output not verifiable
      against the pump (§1.2), or otherwise not yet promotable

## Safety

- [ ] Does **not** weaken the bolus-confirm interlock (touch 1-2-3 / two-button hold) — it stays a
      deliberate second factor on top of the host's confirm + max-bolus clamp
- [ ] Delivery disposition unchanged (**NO-GO for real insulin delivery**) — or this PR's explicit
      subject is changing it, and says so
- [ ] Preserves the honest-staleness signal: an unknown-age or stale reading stays `--` / flagged
      stale, never shown as "now" and never a fabricated value (group A / A1)
- [ ] The paused direct-pump/direct-cgm BLE engines are NOT reintroduced to main and no manifest gains a
      BLE permission (P0-c; narrow-main — they live on dev/direct-ble + experimental) — or this PR's
      explicit subject is that hold, and says so

## Contract (schema mirror)

- [ ] Did **not** touch the phone↔remote contract
- [ ] — or did, and: bumped the schema `version` in faBolus, updated the Monkey C mirror
      (`RemoteComm.mc` / `AppState.mc`) **and** `schema/remote-keys.txt`, kept changes additive/optional,
      and `scripts/check-schema-drift.sh` passes against the matching faBolus branch

## Verification

<!-- CI's Garmin coverage is only the schema-drift contract check + the SBOM check (the SDK/simulator
     can't run in cloud CI — see .github/workflows/ci.yml). The build + 29-case unit suite is a LOCAL
     gate; paste what you ran. -->

- [ ] `./scripts/build-and-test.sh` (compiles every jungle + runs the Monkey C unit suite in the sim)
- [ ] `./scripts/check-schema-drift.sh` passes (with the sibling faBolus checkout)
- [ ] `./scripts/check-sbom.sh` passes
- [ ] Hardware-tested vs. compile-only noted (venu3s is the only hardware-validated device)

## Cross-repo

- [ ] N/A — single repo
- [ ] Touches the contract or a shared constant → sibling faBolus PR linked, and the branch-aware CI
      resolved the matching faBolus branch (check the `fbref` log line for the ref **and SHA**)
