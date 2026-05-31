# Supported foot switch devices

USB HID foot switches this app can detect and program. The `program` column is
the protocol variant (the original `footswitch` CLI uses different report layouts
per family). IDs are hex (USB idVendor:idProduct).

| vendorId | productId | program     |
|----------|-----------|-------------|
| 0c45     | 7403      | footswitch  |
| 0c45     | 7404      | footswitch  |
| 413d     | 2107      | footswitch  |
| 1a86     | e026      | footswitch  |
| 3553     | b001      | footswitch  |
| 0426     | 3011      | scythe      |
| 055a     | 0998      | scythe2     |
| 5131     | 2019      | footswitch1p|

The unit on hand (verified via `ioreg`) reports `idVendor=13651 (0x3553)`,
`idProduct=45057 (0xb001)`, "PCsensor / FootSwitch" — i.e. the `3553:b001`
`footswitch` variant.
