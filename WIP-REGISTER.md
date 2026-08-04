# WIP register — faBolusGarmin

**Created:** 2026-08-04, per §0.1 of `faBolus-handoff-v3.md`.

**State at capture:** `git status` clean · no stashes · nothing unpushed · no pull requests ever opened.

**Disposition key:** **R** = resume after restructuring · **F** = fold into the v3 plan · **A** = abandon ·
**N** = not our WIP (platform-blocked or deliberate permanent design).

> v3 §1.5 is explicit that Garmin is a **base feature** held to the same `main` quality bar as the app,
> and that the Garmin defects A2, C2, E3, E4, E5 are release-blocking. Items 1–3 below mean that today
> **nothing in this repository is verified automatically at all.** Fix those first; they are cheap.

---

## 1. CI and branches — all currently broken or stale

| # | Item | Evidence | Disp. | Note |
|---|---|---|---|---|
| 1 | **CI never runs.** The workflow triggers on `master` only; the live default branch is `main`. | `.github/workflows/ci.yml:4-8`; `origin/HEAD -> origin/main` | **F** | No push or PR on `main` has ever run CI. One-line fix. |
| 2 | **No `monkeyc` step exists.** CI's single job runs only `scripts/check-schema-drift.sh` on Ubuntu. | `.github/workflows/ci.yml` | **F** | The whole Monkey C unit suite (`tests/{ParityTest,ResponsesTest,ResumeTest,TestEntryApp}.mc`, all `(:test)`-annotated and active) runs only via a manual `monkeyc -f test.jungle --unit-test` + `monkeydo`. This is the "no runnable app-layer harness" gap recorded at `faBolus-internal/auditor-response-2026-07-23-round3.md:135`. |
| 3 | `origin/master` — stale abandoned remote branch, 0 ahead / 25 behind `origin/main` | `38f430e` (2026-07-21) vs `659dc34` (2026-07-23) | **A** | The pre-rename default. Root cause of item 1. Delete after the `deprecated` tag. |
| 4 | `remediation/audit-round3-2026-07-24` — bare label, identical SHA to `main`, local-only | 0 ahead / 0 behind | **A** | No round-3 work landed here. |
| 5 | `remediation/audit-2026-07` — local-only, 0 ahead, merged | | **A** | Stale pointer. |
| 6 | **A fresh clone cannot build the shipping app.** `monkey.jungle:19` / `official.jungle:9` require `barrels/EatingSense.barrel`, which `.gitignore` (`barrels/*.barrel`) keeps uncommitted. | exists locally only | **F** | Either commit the barrel, make the barrel path optional, or document the private-SDK build step as a hard prerequisite. |

## 2. Paused feature trees (all deliberately excluded from shipping builds)

| # | Item | Evidence | Disp. | Note |
|---|---|---|---|---|
| 7 | **`direct-pump/` (26 files) — excluded, with two independent locks** | shipping jungles set `base.sourcePath = source/app` only (`monkey.jungle:14`, `official.jungle:5`), stated at `monkey.jungle:11-12`; and `manifest.xml`/`manifest-official.xml` declare **no `BluetoothLowEnergy` permission** | **R** | **Keep excluded.** This is a standing hold (`faBolus-internal/REMEDIATION.md:111` P0-c) and also a v3 C9 conflict — a Garmin watch talking straight to the pump is a second connection holder. Blocked in any case on unimplemented pure-Monkey C secp256r1 EC-JPAKE (`direct-pump/DIRECT_PUMP_STATUS.md:32` calls this "the crux"). The engine itself is byte-exact vs the oracle with 31-32 unit tests — the highest-value parked asset here. |
| 8 | `direct-pump/harness/` (4 files) — compiled by **no** jungle | `DIRECT_PUMP_STATUS.md:51-52` "Archived; not compiled" | **A** | Bring-up UI, superseded. |
| 9 | `direct-pump/transport/` (`DirectTransport.mc`, `StatusFeed.mc`) — compiled by no jungle; coupled to a `RemoteComm` router that no longer exists | `DIRECT_PUMP_STATUS.md:48-50`; `source/app/RemoteComm.mc:11` | **R** | Dead until rewired. Note `StatusFeed.mc:11` also contains a **duplicate client-side trend-arrow derivation** — see the Reconciliation Report on C8/E8; delete it rather than rewire it. |
| 10 | `direct-pump/transport/DirectTransport.mc:172` — `glucoseAgeSec = 0; // read just now; TODO map pump epoch precisely` | | **F** | The only live TODO in Garmin product code. Unreachable today (item 9), but it is the same "stamp it now" pattern as v3 defect A1 — fix it whenever this tree is revived. |
| 11 | `direct-cgm/` (5 files) — "paused / compile-verified only", not wired into `AppState.glucose` | `DIRECT_CGM_STATUS.md:1,5`; `README.md:77` | **R** | Needs a live G7. v3 §4.1 argues direct CGM should stay a labelled, default-off fallback — consistent with leaving this parked. |
| 12 | `tools/gen_golden.sh` + `tests/golden_vectors.txt` regeneration needs a JDK and PumpX2Kit's oracle submodule | `DIRECT_PUMP_STATUS.md:56-57` | **N** | Manual cross-repo step by design. |

## 3. Platform-blocked and deliberately dormant

| # | Item | Evidence | Disp. | Note |
|---|---|---|---|---|
| 13 | `datafield/FaBolusDataField.mc:19-21` — `compute()` returns the literal `"--"` forever | Connect IQ forbids `ComplicationSubscriber` for `type=datafield` (`:7-12`); `manifest-datafield.xml` declares no permissions | **N** | **Permanently** blocked by the platform, not unfinished. Ships as a labelled placeholder. v3 §1.3 asks for a stated minimum device set and graceful failure on unsupported hardware — this is the pattern, but the label should say "not possible on this app type", not merely "--". |
| 14 | `CONTRIBUTING.md:60` — stale reference to "the TODO in `watchface/FaBolusFaceView.mc`" | that file has no TODO and *does* subscribe to the complication (`:28-40`, `:55-75`) | **F** | Doc understates the watch face. Correct it. |
| 15 | `CONTRIBUTING.md:68` — Connect IQ **widget** app type "not built" | | **R** | Never started. |
| 16 | Official Connect IQ listing dormant; the app defaults to Beta | `docs/STORE-BUILDS.md:15` | **R** | Standing hold (`faBolus-internal/REMEDIATION.md:113`). **Do not publish.** |
| 17 | Only venu3s is hardware-validated; fr265s / fenix7 / fr245 / edge540 / edge1040 are compile-only | `store/connectiq-listing.md:31` | **F** | This *is* the "stated minimum supported Garmin device set" that v3 §1.3 asks for — it exists but is buried in a store listing. Promote it to a published compatibility floor, and test the lowest-capability device in the set (fr245, which is CIQ 3.3 and already needs the `complications`/`nocomplications` split at `monkey.jungle:30`). |

## 4. Build-flag equivalents (recorded for completeness)

Monkey C has no `#if`; the equivalents are jungle `excludeAnnotations`, per-device `resourcePath`, and
manifest permissions. All are working as designed — **N**:

- `base.excludeAnnotations = nocomplications` (`monkey.jungle:21`, `official.jungle:11`) and
  `fr245.excludeAnnotations = complications` (`monkey.jungle:30`, `official.jungle:20`), with the real
  publisher at `source/app/BgComplication.mc:66` `(:complications)` and the no-op stub at `:113`
  `(:nocomplications)`.
- Per-device resource exclusion for `edge540`, `edge1040`, `fr245`.
- Other annotations: `(:background)` (`BgService.mc:12,42`), `(:glance)` (`FaBolusGlanceView.mc:11`).
- `.gitignore` reserves untracked personal-build artifacts: `.beta-app-id`,
  `manifest-beta-local.xml`, `beta-local.jungle` (generated by `scripts/beta-build.sh`).
- `source/app/AppState.mc:315` — the carb path deliberately returns 0 and `carbCalcAvailable()` is
  false rather than guessing a carb ratio. Intentional fail-closed; keep.

---

## Negative results

- No `FIXME`, `HACK`, or `XXX` anywhere. Four strict `TODO` hits total (items 10, 14, and two
  data-field/watch-face notes).
- No skip/disable annotations in the Monkey C test suite — every `(:test)` function is active. The
  problem is that nothing *runs* them (items 1-2).
- No `System.error` / throw-unsupported stubs; no unreferenced types.
- Zero genuine commented-out code blocks over 5 lines (the 5-line run in
  `direct-pump/engine/auth/ResumeCoordinator.mc:24-28` is an ASCII flow diagram in a doc comment).
- Scans covered git-tracked files only; `bin/`, `gen/`, `*.iq`, `*.prg`, `barrels/*.barrel` and the
  signing keys were out of scope by construction.
