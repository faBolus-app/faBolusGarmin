# Third-party notices — faBolusGarmin

This file is the findable **index** to faBolusGarmin's licensing and attribution. The authoritative
prose stays in `NOTICE.md`; the machine-checkable component table stays in `docs/SBOM.md`.

| Where | What it covers |
|---|---|
| [`LICENSE`](LICENSE) | The project license — **MIT** (© 2026 the faBolus authors). Covers this repo's source code. |
| [`NOTICE.md`](NOTICE.md) | Attribution prose: the faBolus™ trademark, the ported calculator's upstreams, and the third-party trademarks. |
| [`LICENSES/`](LICENSES) | The upstream license texts the port carries: pumpX2 and LoopKit. |
| [`docs/SBOM.md`](docs/SBOM.md) | The component table: first-party app, the ported calculator, and the license-gated Connect IQ SDK (not vendored). Checked by `scripts/check-sbom.sh`. |

## Summary

faBolusGarmin is an independent, open-source **Monkey C** app licensed under the **MIT License**. It
carries **no vendored third-party runtime source in the shipping build**. The only external component a
shipping build needs is **license-gated and not vendored** into this repo:

- the **Garmin Connect IQ SDK / Monkey C runtime** (Garmin-proprietary, EULA-gated).

One file ports third-party logic, by way of faBolus's Swift: `source/app/Calculator.mc`, the bolus
calculator, from **pumpX2**'s `BolusCalculator` (MIT, © 2022 James Woglom) and **LoopKit**'s bolus-volume
round-down (MIT, © 2018 and © 2020 LoopKit Authors). Its test rows in `contract/bolus_oracle_fixtures.jsonl`
are that pumpX2 calculator's outputs.

The **faBolus™** name is a trademark of Zev Granowitz — the MIT license covers the code, not the name or
branding.
