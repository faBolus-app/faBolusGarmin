# Third-party notices — faBolusGarmin

This file is the findable **index** to faBolusGarmin's licensing and attribution. The authoritative
prose stays in `NOTICE.md`; the machine-checkable component table stays in `docs/SBOM.md`.

| Where | What it covers |
|---|---|
| [`LICENSE`](LICENSE) | The project license — **MIT** (© 2026 the faBolus authors). Covers this repo's source code. |
| [`NOTICE.md`](NOTICE.md) | Attribution prose: the faBolus™ trademark, the pumpX2 protocol reference (© James Woglom, MIT), the G7SensorKit / xDripG5 / CGMBLEKit lineage (MIT), and the third-party trademarks. |
| [`docs/SBOM.md`](docs/SBOM.md) | The component table: first-party app, the credential-gated Connect IQ SDK + `EatingSense.barrel` (not vendored), and the in-tree ported source in the paused `direct-cgm/` / `direct-pump/` engines. Checked by `scripts/check-sbom.sh`. |

## Summary

faBolusGarmin is an independent, open-source **Monkey C** app licensed under the **MIT License**. It
carries **no vendored third-party runtime source in the shipping build**. The only external components a
shipping build needs are **license/credential-gated and are not vendored** into this repo:

- the **Garmin Connect IQ SDK / Monkey C runtime** (Garmin-proprietary, EULA-gated), and
- the private **`EatingSense.barrel`** built from the faBolusNudge SDK (MIT code; `.gitignore`d, a hard
  build prerequisite).

Two **paused, non-shipping** engines carry ported/reference third-party lineage, recorded in `NOTICE.md`
and `docs/SBOM.md` for provenance honesty: the `direct-cgm/` G7 decoder (ported from LoopKit/G7SensorKit,
MIT) and the `direct-pump/` engine (an independent reimplementation of the Tandem protocol
reverse-engineered by jwoglom/pumpX2, MIT). Neither is part of any shipping build.

The **faBolus™** name is a trademark of Tia Geri — the MIT license covers the code, not the name or
branding.
