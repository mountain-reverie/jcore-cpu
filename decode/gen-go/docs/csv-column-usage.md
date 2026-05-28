# CSV column usage histogram

Generated 2026-05-20 by `cmd/csv2toml -histogram`. Columns with count 0
carry no information and are dropped from the TOML schema. Columns with
low counts are reviewed by hand to confirm they aren't always-default
artifacts.

| Column | Non-empty row count |
|---|---|
| ALU X | 6 |
| ALU Y | 76 |
| ARITH | 114 |
| ARITH SR | 12 |
| CARRYIN EN | 3 |
| COPROC CMD | 8 |
| DATA MUX | 2 |
| DEBUG | 2 |
| DELAY JMP | 10 |
| DISPATCH | 13 |
| EVENT | 3 |
| Format | 150 |
| HALT | 1 |
| IF ADDY | 19 |
| IF ISSUE | 22 |
| ILEVEL CAPTURE | 2 |
| Instruction | 254 |
| LOGIC | 20 |
| LOGIC SR | 7 |
| Latch S_MAC | 2 |
| MA ADDY | 78 |
| MA DATA | 36 |
| MA LOCK | 6 |
| MA MASK | 1 |
| MA OP | 78 |
| MA SIZE | 78 |
| MAC BUSY | 10 |
| MAC OP | 7 |
| MAC STAGE | 14 |
| MAC STALL SENSE | 14 |
| MACH | 3 |
| MACIN_1 | 10 |
| MACIN_2 | 10 |
| MACL | 3 |
| MANIP | 8 |
| MASK INT | 29 |
| Op Code | 254 |
| Operation | 155 |
| PC | 254 |
| PR | 3 |
| Plane | 45 |
| SHIFT | 16 |
| SR | 37 |
| State | 145 |
| TABLE | 143 |
| WBUS | 31 |
| XBUS | 163 |
| YBUS | 143 |
| ZBUS | 124 |
| ZBUS SEL | 172 |

## Decision

Drop from TOML schema: none

Keep but flag in validator as rare: CARRYIN EN (3), DATA MUX (2), DEBUG (2), EVENT (3), HALT (1), ILEVEL CAPTURE (2), Latch S_MAC (2), MA MASK (1), MACH (3), MACL (3), PR (3)

These 11 columns appear in fewer than 5 rows each. While they don't warrant removal, they should be validated carefully during TOML emission to ensure they truly represent intentional signal assignments and not data entry artifacts.
