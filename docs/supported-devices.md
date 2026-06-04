# Supported foot switch devices

Foot switches this app can detect and program. Most connect over USB HID;
the FS17Pro also connects over Bluetooth LE. The `program` column is
the protocol variant (the original `footswitch` CLI uses different report layouts
per family). IDs are hex (USB idVendor:idProduct).

| vendorId | productId | program       |
|----------|-----------|---------------|
| 0c45     | 7403      | footswitch    |
| 0c45     | 7404      | footswitch    |
| 413d     | 2107      | footswitch    |
| 1a86     | e026      | footswitch    |
| 3553     | b001      | footswitch    |
| 3553     | c100      | footswitch    |
| 245a     | 8276      | footswitchBLE |
| 0426     | 3011      | scythe        |
| 055a     | 0998      | scythe2       |
| 5131     | 2019      | footswitch1p  |

The unit on hand (verified via `ioreg`) reports `idVendor=13651 (0x3553)`,
`idProduct=45057 (0xb001)`, "PCsensor / FootSwitch" — i.e. the `3553:b001`
`footswitch` variant.

The PCsensor **FS17Pro** is a single logical device that enumerates differently
per mode: `3553:c100` over USB wired mode and `245a:8276` over Bluetooth LE.
The app programs it over whichever transport it's connected on. Use trigger key
**F16** (ElfKey, PCsensor's own config tool, cannot assign F13–F15).

## Multi-pedal devices

Pedal count is **detected at runtime**, not recorded in this table: multi- and
single-pedal PCsensor units typically share the same VID/PID and `footswitch`
family (the pedal count is a hardware SKU difference), so a static column would
misreport it. On a connected `footswitch`-family USB device the app probes each
pedal slot (1–3) for a readable stored config and programs each present pedal
independently — slot _i_ maps to the device's 0-based `pedalIndex` _i−1_. Default
trigger keys are F13 / F14 / F15 for pedals 1 / 2 / 3. Bluetooth (FS17Pro) remains
single-pedal.
