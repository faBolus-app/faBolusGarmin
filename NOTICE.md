# Attributions

faBolusGarmin is an independent, open-source project, licensed under the MIT License (see `LICENSE`).

## The faBolus™ name

**faBolus™** (including **faBolusGarmin**) is a trademark of Tia Geri. The MIT License covers this
project's **source code**; it does not grant any right to use the "faBolus" name, logo, or branding.
You are free to fork and reuse the code under the MIT terms, but please do not use the faBolus name
in a way that suggests your fork is the official project or is endorsed by it.

It is the Garmin (Connect IQ / Monkey C) remote for **faBolus**, and its direct-to-pump engine is an
independent reimplementation of the Tandem pump Bluetooth protocol as reverse-engineered by the
**[pumpX2](https://github.com/jwoglom/pumpx2)** project (© James Woglom, MIT License). It is **not** a
fork of, affiliated with, or endorsed by pumpX2/controlX2.

## G7SensorKit (Dexcom G7 / ONE+ decoding)

The direct-CGM engine (`direct-cgm/engine/G7Message.mc`) is a Monkey C port of the Dexcom G7 /
ONE+ decoders from **[LoopKit/G7SensorKit](https://github.com/LoopKit/G7SensorKit)** (© 2022 LoopKit
Authors; portions originate in xDripG5 / CGMBLEKit, © 2015–2016 Nathan Racklyeft), used under the
MIT License. It is passive/read-only — it only parses the broadcast the official Dexcom app already
authenticated.

Not affiliated with, endorsed by, or a product of **Tandem Diabetes Care**, **Dexcom**, or
**Garmin**. Tandem, t:slim X2, Mobi, Dexcom, and Garmin are trademarks of their respective owners.
