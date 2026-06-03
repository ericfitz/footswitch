# FS17Pro BLE Programming Protocol — Reverse-Engineering Notes

Date: 2026-06-02
Status: Findings (input to the FS17Pro support design)

Source: Apple PacketLogger BTSnoop capture `~/Desktop/fs17pro.btsnoop` (477
frames), taken while PCsensor **ElfKey** reprogrammed the FS17Pro **to F16 over
Bluetooth LE**. Decoded with `tshark` 4.6.

## Headline

**ElfKey programs the FS17Pro over BLE**, and the wire protocol is the **same
PCsensor `.footswitch` report sequence the app already implements for USB** — just
carried as **GATT ATT Write Requests** instead of USB HID output reports, with a
`0x01` report-ID byte prepended to each report and the read-back arriving as a GATT
**notification**.

This means BLE programming is feasible by reusing `FootswitchProgram` almost
verbatim; only the transport layer is new.

## Connection topology

Three LE connections were active; traffic split by ACL connection handle:

- `0x0011` — 393 Rcvd frames, device→host HID **input** (keyboard/streaming). Not
  programming. (The F16/F17 keypress input reports seen here are normal HID input,
  initially misread as the pedal.)
- `0x004d` — **the footswitch programming connection.** 3 host→device ATT writes +
  read-back notifications, all on ATT channel **CID 0x0004**.
- `0x0010` — 2 frames, incidental.

## The programming exchange (handle 0x004d, ATT CID 0x0004)

| # | Dir   | ATT opcode            | Handle | ATT value (hex)         |
|---|-------|-----------------------|--------|-------------------------|
| 265 | →dev | Write Request (0x12)  | 0x0017 | `01 01 81 08 02 00 00 00 00` |
| 271 | ←dev | Write Response (0x13) | 0x0017 | —                       |
| 272 | →dev | Write Request (0x12)  | 0x0017 | `01 08 81 00 6b 00 00 00 00` |
| 275 | ←dev | Write Response (0x13) | 0x0017 | —                       |
| 283 | ←dev | Notification (0x1b)   | 0x0019 | `01 81 55`              |
| 288 | →dev | Write Request (0x12)  | 0x0017 | `01 01 82 08 02 00 00 00 00` |
| 292 | ←dev | Write Response (0x13) | 0x0017 | —                       |
| 297 | ←dev | Notification (0x1b)   | 0x0019 | `01 08 81 00 6b 00 00 00 00` |

### Decode (report-ID byte + 8-byte PCsensor report)

Each ATT value = a leading **`0x01` report-ID byte** followed by the same 8-byte
report `FootswitchProgram` builds for USB:

- **Frame 265 — header write:** report `[0x01,0x81,0x08, 0x02, 0,0,0,0]`
  = `keyReports().header` with `pedalIndex+1 = 2` → **programming pedal 2**.
- **Frame 272 — data write:** report `[0x08, 0x81, 0x00, 0x6b, 0,0,0,0]`
  = data report: length `0x08`, **type `0x81`**, modifiers `0x00`, **usage `0x6b`
  = F16**.
- **Frame 288 — query/read-back:** report `[0x01,0x82,0x08, 0x02, 0,0,0,0]`
  = `FootswitchProgram.queryReport(pedalIndex: 1)` (pedal 2).
- **Frame 297 — read-back reply (notification):** `[0x08,0x81,0x00,0x6b,…]`
  → `parseKeyResponse` decodes `type=0x81, usage=0x6b` → **F16**. Confirms the
  write took.
- **Frame 283 — interim notification `01 81 55`:** short status/ack notification
  (3 bytes). Likely a progress/echo; not required to parse for programming.

## Differences vs the current USB code (`FootswitchProgram`)

1. **Report-ID prefix.** USB passes report ID `0x01` to `IOHIDDeviceSetReport`
   separately; BLE includes it **inline** as the first value byte. The remaining 8
   bytes are identical to our USB reports.

2. **Data-report type byte `0x81` vs `0x01`.** Our `keyReports()` emits
   `keyType = 0x01` (`data = [0x08, 0x01, mod, usage, …]`). The BLE capture writes
   `0x81` (`[0x08, 0x81, mod, usage, …]`). The existing read parser already accepts
   both (`parseKeyResponse` matches `case 1, 0x81`), suggesting `0x81` is the
   firmware's canonical "key" type. **To verify:** whether USB also accepts/echoes
   `0x81`, and whether BLE requires the high bit. Low risk either way — a one-byte
   constant.

3. **Pedal index.** ElfKey programmed **pedal 2** (`pedalIndex+1 = 0x02`). The
   FS17Pro is single-pedal in our usage; confirm whether it indexes from 1 or 2 for
   the (only) pedal before relying on a hard-coded index.

## GATT layout (resolved via read-only CoreBluetooth discovery)

A read-only CoreBluetooth scan of the connected FS17Pro resolved the handles from
the capture to stable UUIDs:

- **Vendor service `FFF0`** (primary) — the config service used by the capture:
  - **`FFF2` — properties `[write, writeNoResp]`** → the **config WRITE**
    characteristic (capture handle `0x0017`). Header/data/query reports are
    written here.
  - **`FFF1` — properties `[notify]`** → the **read-back / status NOTIFY**
    characteristic (capture handle `0x0019`). The stored-config reply and the
    interim `01 81 55` status arrive here.
- Also present (not used by the captured exchange):
  - Standard **Device Information** and **Battery** services (PnP ID, Battery
    Level).
  - A 128-bit vendor service `00010203-0405-0607-0809-0A0B0C0D1912` with char
    `…2B12 [read, writeNoResp]` and a branded char
    `6971656B-676E-6179-6971-656B676E6179` (ASCII "qiekgnayqiekgnay") — an
    alternate/OTA config path. The `FFF0` path is the one ElfKey used and is the
    implementation target.

### Remaining step to confirm at implementation time

- The **CCCD write** that enables notifications on `FFF1` must happen before
  programming so the read-back is received. CoreBluetooth's
  `setNotifyValue(true:)` handles this automatically. Not separately visible in the
  capture (it began mid-connection), but it is a standard, required GATT step.

## BLE programming recipe (complete)

1. Obtain the peripheral via `retrieveConnectedPeripherals(withServices: [1812])`
   (the pedal is bonded as a HID keyboard; it does **not** advertise connectably,
   so `scanForPeripherals` will time out — this was confirmed).
2. Discover service `FFF0`; get characteristics `FFF2` (write) and `FFF1`
   (notify).
3. `setNotifyValue(true)` on `FFF1`.
4. Write to `FFF2` (Write Request): `[0x01] + header`, then `[0x01] + data`, then
   `[0x01] + query` — bytes from `FootswitchProgram` (type byte `0x81`).
5. On the `FFF1` notification, strip the leading `0x01` and decode with
   `parseKeyResponse` to confirm.

## Implication for the design

BLE programming is **viable** and largely reuses `FootswitchProgram`. A future
implementation would:
1. Connect to the FS17Pro over CoreBluetooth, discover the vendor service +
   write/notify characteristics (resolve the `0x0017`/`0x0019` UUIDs).
2. Subscribe to the notify characteristic (write CCCD).
3. Write `[0x01] + header`, `[0x01] + data`, `[0x01] + query` as ATT writes, using
   `FootswitchProgram` bytes (with the `0x81` type byte and report-ID prefix).
4. Parse the read-back notification via `parseKeyResponse` (strip the leading
   `0x01`).

This is a transport adapter over the existing report builder — not a new protocol.
Whether to build it now (BLE programming, no USB cable) or keep USB-only
programming for the first release is a scope decision for the design.
