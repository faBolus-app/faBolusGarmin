# Attributions

faBolusGarmin is an independent, open-source project, licensed under the MIT License (see `LICENSE`).

## The faBolus™ name

**faBolus™** (including **faBolusGarmin**) is a trademark of Zev Granowitz. The MIT License covers this
project's **source code**; it does not grant any right to use the "faBolus" name, logo, or branding.
You are free to fork and reuse the code under the MIT terms, but please do not use the faBolus name
in a way that suggests your fork is the official project or is endorsed by it.

It is the Garmin (Connect IQ / Monkey C) remote for **faBolus**.

## Ported logic

`source/app/Calculator.mc` is a hand port of faBolus's bolus calculator, itself a port of
**[pumpX2](https://github.com/jwoglom/pumpx2)**'s `BolusCalculator` (© 2022 James Woglom, MIT License),
with **[LoopKit](https://github.com/LoopKit/LoopKit)**'s round-down to the pump's bolus step (© 2018 and
© 2020 LoopKit Authors, MIT License). Its test rows, `contract/bolus_oracle_fixtures.jsonl`, are outputs of
pumpX2's calculator. Their license texts are in [`LICENSES/pumpx2.txt`](LICENSES/pumpx2.txt) and
[`LICENSES/LoopKit.txt`](LICENSES/LoopKit.txt).

Not affiliated with, endorsed by, or a product of **Tandem Diabetes Care**, **Dexcom**, or
**Garmin**. Tandem, t:slim X2, Mobi, Dexcom, and Garmin are trademarks of their respective owners.
