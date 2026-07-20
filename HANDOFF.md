# faBolusGarmin — Handoff

You are starting a **new, independent project**: a **standalone Garmin Connect IQ (Monkey C)
app that talks directly to a Tandem t:slim X2 / Mobi pump over Bluetooth — no phone in the
loop.** This is Milestone 5 of the larger effort. It shares **no code** with the Swift stack;
it is a full reimplementation of the pump's protocol + auth + BLE in Monkey C.

> [!WARNING]
> **Bench proof-of-concept only.** All testing uses a dedicated test pump dispensing **saline
> into a container on a scale — never on a body.** The dosing path is signed/authorized and is
> the most safety-critical code; it must be validated byte-exact against the oracle before it
> ever drives a pump. This is an independent reimplementation, **not** affiliated with or
> endorsed by Tandem, jwoglom (pumpX2/controlX2), or Garmin.

---

## 0. Read this first: two GO/NO-GO gates

Do **not** build features before proving these two things. Either one can kill the project;
find out cheaply.

### Gate A — Can Connect IQ BLE bond + talk to the pump?
The pump requires a **bonded/encrypted** BLE connection to a custom GATT service. Prove CIQ can
do it on the target watch (venu3s) before anything else:

1. Confirm the venu3s (and your target devices) actually support `Toybox.BluetoothLowEnergy`
   (not all CIQ devices do — check the device's capabilities / try `BluetoothLowEnergy has :…`).
2. Write a throwaway app: `registerProfile` for the pump service `0000FDFB-…` with its
   characteristics, `setScanState(SCAN_STATE_SCANNING)`, find the pump in `onScanResults`,
   `pairDevice()`, then **`Device.requestBond()`** and confirm you reach a bonded/connected
   state and can **subscribe (CCCD write) + receive a notification** from `CURRENT_STATUS`.
3. Watch out for CIQ limits: `registerProfile` caps the number of profiles/characteristics
   (historically small — you may not be able to register all 6 characteristics at once; you may
   need to register only the ones you use). Only one BLE connection at a time. The pump also
   enforces **one control connection** — you cannot coexist with the phone app.

If CIQ can't establish the bonded connection the pump needs, **standalone Garmin isn't viable**
and the phone-relay design (already shipped in `faBolus/garmin`) remains the answer.

### Gate B — Can you do EC-JPAKE on Monkey C?
Modern pumps (Mobi, t:slim X2 v7.7+) require **6-digit pairing via EC-JPAKE** (secp256r1 /
SHA-256). This is the hardest part.

What CIQ's `Toybox.Cryptography` gives you (verified in SDK 9.2.0):
- `Hash` (SHA-1, SHA-256), `HashBasedMessageAuthenticationCode` (**HMAC-SHA256 only**),
  `Cipher` (AES-128/256), `CipherBasedMessageAuthenticationCode` (AES-CMAC), `randomBytes()`.
- `KeyPair` for **secp256r1** (`KEY_PAIR_ELLIPTIC_CURVE_SECP256R1`) and **ECDH key agreement**
  (`KEY_AGREEMENT_ECDH`), `createPublicKey`.

What's **missing** and is the core research question:
- **No EC-JPAKE primitive**, and **no exposed raw EC point arithmetic** (only whole-KeyPair +
  ECDH shared-secret). EC-JPAKE needs scalar-mult of *arbitrary* points, point addition, and
  Schnorr zero-knowledge proofs — ECDH alone does **not** give you these. Options, in order of
  preference to investigate:
  1. See whether the JPAKE rounds can be expressed using only `KeyPair`/ECDH/`createPublicKey`
     operations (likely **not** sufficient — but confirm).
  2. Implement secp256r1 point arithmetic in pure Monkey C (bignum mod p + curve ops). Heavy,
     slow, and error-prone, but it's the realistic path. Validate every step against the oracle.
  3. Reconsider scope: support only the **legacy 16-char pairing** path first (no EC-JPAKE) if
     the bench pump's firmware allows it — get an end-to-end bonded+authenticated read working,
     then tackle JPAKE.
- **HMAC-SHA1 is needed** for packet signing (see §3) but CIQ HMAC is SHA-256-only. This one is
  easy: implement HMAC-SHA1 yourself from the SHA-1 `Hash` primitive
  (`HMAC(K,m) = H((K⊕opad) ‖ H((K⊕ipad) ‖ m))`). Validate against the oracle.

Prove you can derive the **same JPAKE shared secret as the oracle** (`jpake-server`) before
building the app around it.

---

## 1. What "done" looks like
A venu3s app that, with no phone: scans → bonds → pairs (6-digit or legacy) → reads status/IOB/
CGM → delivers a **gravimetrically-verified saline bolus** → cancels mid-delivery — every
outgoing message **byte-exact** vs the cliparser oracle.

Then (only after that): a UI modeled on the already-built phone-relay Garmin app.

---

## 2. Reference material (read, don't re-derive)

All paths are siblings under a common parent directory (clone the GitHub repos side by side if on
a fresh machine):

- **`PumpX2Kit/`** (github.com/zgranowitz/PumpX2Kit) — **your primary reference.** A
  Swift port of the whole protocol/auth/BLE, validated **byte-exact** against the oracle. Port
  its logic to Monkey C. Key files:
  - `Sources/PumpX2Messages/Core/Packetize.swift` — framing + signing (the spine).
  - `Sources/PumpX2Messages/Helpers/Bytes.swift` — CRC-16, LE int read/write.
  - `Sources/PumpX2Messages/Bluetooth/{ServiceUUID,Characteristic}.swift` — UUIDs, MTU.
  - `Sources/PumpX2Messages/Requests/…`, `Responses/…` — every message + opcode + cargo layout.
  - `Sources/PumpX2Auth/{Crypto,JpakeAuth,PairingCoordinator,PairingAuth}.swift` — HMAC/HKDF,
    the JPAKE rounds (rounds 1–2 + derive via mbedTLS; rounds 3–4 Tandem-specific), legacy pair.
  - `Sources/PumpX2BLE/PumpBLEClient.swift` — connect/discover/subscribe/reassemble/write flow.
  - `Tests/PumpX2MessagesTests/OracleParityTests.swift` — how to diff against the oracle.
- **`references/pumpx2/`** (github.com/jwoglom/pumpx2, Java) — the upstream ground truth + the
  **cliparser oracle** (`vendor/pumpx2-oracle` in PumpX2Kit builds it; `encode`/`parse`/
  `jpake-server` subcommands). Use it to validate your Monkey C bytes.
- **`references/controlX2/`** (github.com/jwoglom/controlX2) — Android/**Wear OS** reference. The
  `wear/` module is the closest existing "watch" client; mine it for the connection lifecycle,
  the notification/bolus flows, and `NotificationBundle`.
- **`faBolus/garmin/`** (github.com/zgranowitz/faBolus) — the **phone-relay** Garmin
  app already built for the venu3s. Reuse its **UI patterns and hard-won venu3s constraints**
  (see §5), the Loop-style screens, the 1-2-3 confirm, the Dexcom-style history plot, the
  complication. This new app replaces its *transport* (direct BLE instead of phone messages),
  not its UX.

---

## 3. Protocol quick reference (see PumpX2Kit for exact bytes)

- **Service UUID:** `0000FDFB-0000-1000-8000-00805F9B34FB`. Preferred **MTU 185**.
- **Characteristics** (`7B83FFFx-9F77-4E5C-8064-AAE2C24838B9`):
  `FFF6` CURRENT_STATUS, `FFF7` QUALIFYING_EVENTS, `FFF8` HISTORY_LOG, `FFF9` AUTHORIZATION,
  `FFFC` CONTROL, `FFFD` CONTROL_STREAM.
- **Packet framing** (`Packetize`): a message = `[opcode, txId, cargoLen, cargo…, crc16(2)]`,
  chunked to the MTU across multiple BLE writes; reassemble on read. CRC-16 over the header+cargo.
- **Signed messages** (bolus, cancel, dismiss-notification): the cargo gets a **24-byte HMAC**
  trailer computed with the derived auth key over (message bytes + pump-time-since-reset). Packet
  signing also uses **HMAC-SHA1** internally — implement it from the SHA-1 primitive (Gate B).
- **Message flow:** connect → `ApiVersionRequest` → auth (below) → poll CURRENT_STATUS reads
  (IOB, EGV/CGM, insulin, battery, alerts…) → signed bolus: `BolusPermissionRequest` →
  `InitiateBolusRequest` → poll bolus status → `CancelBolusRequest`. CGM history via
  `HistoryLogStatus`/`HistoryLogRequest` → `HistoryLogStreamResponse` frames on HISTORY_LOG.
- **Auth messages:** legacy `CentralChallenge`/`PumpChallenge`; JPAKE
  `Jpake1a`(op32)/`Jpake1b`(34)/`Jpake2`(36)/`Jpake3SessionKey`(38)/`Jpake4KeyConfirmation`(40)
  on the AUTHORIZATION characteristic. Auth key = `HKDF(serverNonce, derivedSecret)`; a
  quick-pair "resume" path reuses a stored derived secret (rounds 3–4 only).

## 4. Auth detail
Study `PumpX2Auth`. JPAKE = mbedTLS rounds 1–2 + derive, then Tandem rounds 3–4 (HKDF +
HMAC-SHA256). On Monkey C you must replace mbedTLS (Gate B). The oracle's `jpake-server` /
`jpake-server-resume` lets you verify your client derives the identical secret with no hardware.

---

## 5. venu3s device constraints (learned the hard way — see faBolus memory)
- **Two physical buttons only**; a screen **tap fires `onSelect()` (no coordinates)**, NOT
  `onTap` at the behavior layer — but plain `onTap(clickEvent)` with coordinates **does** work
  and is what the shipped app uses for buttons. Swipes = `onNextPage`/`onPreviousPage`;
  swipe-right = `onBack`.
- Touches within ~**81 px of the screen edge** are swipe gestures, not taps — keep tap targets
  centered.
- Multiple tappable targets: use `onTap` coordinate hit-testing (the shipped app’s 1-2-3 confirm
  and alert rows do this). `Selectable`/`onSelectable` proved flaky.
- Round 390×390 AMOLED. Fonts can’t render Unicode arrows — draw trend arrows as shapes
  (`TrendArrow.mc` in the shipped app).
- Build: `monkeyc -f monkey.jungle -o bin/faBolus.iq -y <dev_key.der> -e -r` with the
  Connect IQ SDK; sideload/beta via the Connect IQ store. `hidden`/`private` are invalid on
  module functions.

## 6. Suggested milestones
1. **Gate A** BLE smoke test (bond + subscribe + one CURRENT_STATUS notification).
2. **Gate B** crypto: HMAC-SHA1 from SHA-1; then EC-JPAKE derive == oracle (or legacy pairing).
3. Port framing (`Packetize`, CRC-16, txId) + a few empty-cargo status reads; **byte-exact vs
   oracle** in a unit test harness (mirror `OracleParityTests`).
4. Read path end-to-end on the bench pump (status/IOB/CGM).
5. Signed bolus (permission → initiate → status) + cancel; **gravimetric** validation.
6. UI: port the shipped Garmin app's screens (glance, history, details, alerts, 1-2-3 confirm).

## 7. Repo layout (suggested)
```
faBolusGarmin/
├── HANDOFF.md            (this file)
├── README.md            (independent reimplementation, bench-only disclaimers)
├── manifest.xml         (Bluetooth + needed permissions; product venu3s)
├── monkey.jungle
├── source/
│   ├── ble/             (scan/bond/connect/discover/reassemble/write)
│   ├── protocol/        (Packetize, CRC, messages, opcodes)
│   ├── auth/            (HMAC-SHA1, HKDF, JPAKE or legacy pairing)
│   └── ui/              (glance, bolus, confirm, history, alerts)
└── tools/               (oracle-diff harness / notes)
```

## 8. Open questions / risks (in priority order)
1. **EC-JPAKE on Monkey C** (Gate B) — the single biggest risk. Resolve before committing.
2. **CIQ BLE bonding to the pump** (Gate A) — device support + `registerProfile` limits +
   exclusive-connection behavior.
3. **HMAC-SHA1** — easy, but must be byte-verified.
4. **Performance** — bignum EC math in Monkey C may be too slow on-watch; measure early.
5. **Firmware/pairing type** to target first (legacy vs JPAKE) — pick based on the bench pump.

Start with the two gates. Don't write the pretty UI until a signed saline bolus works on the
bench, byte-exact against the oracle.
