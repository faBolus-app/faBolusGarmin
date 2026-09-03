# Third-party notices — faBolusGarmin

This file is the findable **index** to faBolusGarmin's licensing and attribution. The authoritative
prose stays in `NOTICE.md`; the machine-checkable component table stays in `docs/SBOM.md`.

| Where | What it covers |
|---|---|
| [`LICENSE`](LICENSE) | The project license — **MIT** (© 2026 the faBolus authors). Covers this repo's source code. |
| [`NOTICE.md`](NOTICE.md) | Attribution prose: the faBolus™ trademark and the third-party trademarks. |
| [`docs/SBOM.md`](docs/SBOM.md) | The component table: first-party app, and the license-gated Connect IQ SDK (not vendored). Checked by `scripts/check-sbom.sh`. |

## Summary

faBolusGarmin is an independent, open-source **Monkey C** app licensed under the **MIT License**. It
carries **no vendored third-party runtime source in the shipping build**. The only external component a
shipping build needs is **license-gated and not vendored** into this repo:

- the **Garmin Connect IQ SDK / Monkey C runtime** (Garmin-proprietary, EULA-gated).

The **faBolus™** name is a trademark of Zev Granowitz — the MIT license covers the code, not the name or
branding.
