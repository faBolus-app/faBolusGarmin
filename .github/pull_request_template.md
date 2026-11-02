<!--
faBolusGarmin is the Garmin watch app for faBolus, an experimental insulin-pump app (not a medical device,
not FDA-cleared). The watch never doses on its own: it requests, and the phone checks every request.
Fill in what applies; delete what doesn't. See CONTRIBUTING.md, AGENTS.md and BRANCHES.md.
-->

## What & why

<!-- One or two sentences. What changes, and the problem it solves. -->

## Safety

- [ ] Does **not** weaken the bolus confirm (touch 1-2-3 / two-button hold). It is one explicit
      confirmation; the phone's checks are not a second human confirm
- [ ] Keeps the staleness signal: a stale or unknown-age value stays `--` or marked stale, never shown as
      current, never a made-up value
- [ ] Adds no direct-to-pump or direct-to-CGM link, and no manifest gains a Bluetooth permission

## Contract

- [ ] Did **not** touch the phone↔watch contract
- [ ] — or did: the change landed in faBolus's `Packages/RemoteProtocol/contract/` first, `contract/` here
      was updated with `scripts/sync-contract.sh <faBolus-commit>`, and the unit suite passes against it

## Verification

<!-- CI runs ShellCheck, actionlint, markdownlint, the contract check and the SBOM check. The build and
     unit suite need the Connect IQ SDK and simulator, so they run locally: paste what you ran. -->

- [ ] `./scripts/check.sh` (its `build` gate compiles the jungles and runs the unit suite in the simulator)
- [ ] Tested on a watch, or only in the simulator: say which (venu3s is the only device tested on hardware)

## Cross-repo

- [ ] N/A — this repo only
- [ ] Touches the contract or a shared constant → the faBolus pull request is linked, and `contract/PIN`
      names a pushed faBolus commit
