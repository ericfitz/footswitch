# FS17Pro: BLE-programmed key only applies after a physical power-cycle

Date: 2026-06-03
Status: Investigation log (closed — GitHub issue #7)

> **Purpose.** This records a completed, on-device investigation so a future
> attempt at *live-applying* a Bluetooth-programmed key does not repeat the same
> six dead-end probes. The current shipped behavior is correct given these
> findings; this is a knowledge-capture document, not an open task.

## Summary

When the app programs the FS17Pro over **Bluetooth**, the new key is written to the
device's config slot and read-back confirms it — but the pedal keeps emitting the
**old** key until the device is **physically power-cycled**. The app cannot trigger
this reload programmatically. The shipped mitigation is a message after BLE
programming telling the user to power-cycle the pedal
(`alert.programmed.bluetooth`, present in all 30 locales; see also
`device.config.storedBluetooth`).

## Device model (verified on-device 2026-06-03)

- The FS17Pro has a **stored config slot** (queryable over GATT) and a separate
  **live/active keymap** (what the keyboard actually emits).
- A GATT write updates the **slot** immediately (read-back confirms).
- The **live keymap** only reloads from the slots on a **physical device
  power-cycle** — proven: wrote F19 to slot 2, power-cycled, pedal then emitted
  F19.
- A macOS **Settings → Bluetooth "Disconnect"** does NOT apply it (host-side only;
  the device stays powered). Guidance must say "power-cycle the pedal," not
  "disconnect/reconnect in Bluetooth settings."

## What was ruled out (6 probes, none reloaded the live key)

1. GATT write alone (header `81` / data / query `82`) — slot updates, live key
   unchanged.
2. Write + ElfKey's `0x83` identify/handshake (`01 01 83 08 00...`; device replies
   on FFF1 with name "FS17Pro_" + firmware "V1.9") — `0x83` is identify, not apply.
3. Handshake-only re-apply — does not reconcile slot→live.
4. `cancelPeripheralConnection` (drop our GATT link) — no effect.
5. Full CoreBluetooth disconnect+reconnect cycle — no effect.
6. Physical power-cycle — **works.**

## Why the app can't do it

Our CoreBluetooth link to the FFF0 vendor service is separate from the macOS
**system HID-keyboard link**, which macOS owns and keeps alive. There is no public
API for an app to drop the user's HID keyboard link. ElfKey's "live" apply
coincides with system-level HCI Disconnect / LE-Connection-Complete events at its
session start (visible in a full PacketLogger capture) — i.e. ElfKey's connect
cycles the *system* link, which a third-party CoreBluetooth app cannot reproduce.

## GATT reference

- Vendor service **FFF0**, write char **FFF2** (handle 0x0017), notify char
  **FFF1** (handle 0x0019). macOS does not expose the standard HID service
  (0x1812) to third-party CoreBluetooth apps, so the peripheral must be found via
  FFF0.
- BLE programs the single pedal at **pedalIndex 1** (slot 2). Slots also readable
  at index 0 (slot 1) and index 2 (slot 3).
- The FS17Pro stores config **independently per transport** (USB slot ≠ BLE slot).

See the companion protocol spec
[`2026-06-02-fs17pro-ble-programming-protocol.md`](2026-06-02-fs17pro-ble-programming-protocol.md)
for the full GATT write/query framing.

## Possible future directions

- A **"Test" button** (issue #6) sidesteps this: detect the actually-emitted key
  and let the user adopt it into config (no power-cycle) — likely the best UX
  answer.
- Re-examine whether any vendor command in ElfKey's *USB* programming (where it
  applies live) maps to a BLE equivalent we missed.
