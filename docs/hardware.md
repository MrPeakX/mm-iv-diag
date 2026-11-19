# MM IV / MM V hardware reference

Hardware of the Hegener + Glaser Mephisto MM IV and MM V modules
(identical hardware), the 7-segment LCD display unit of the modular
series and the Mephisto sensor boards (Modular, Exclusive, München), as
needed to write software for it.

## 1. CPU, clock, interrupts

| Item  | Value |
|-------|-------|
| CPU   | Rockwell R65C02P3 / R65C02P4, or GTE G65SC02P-4 (unit dependent) |
| Clock | 4.9152 MHz, one cycle = 203.45 ns |
| NMI   | 600 Hz = clock / 8192, from a 74HC4060 14-bit counter |
| IRQ   | not used, IRQ input tied to VSS |
| RAM   | 8 KiB SRAM (150 ns) |

### NMI

- Runs from power-on and cannot be masked or disabled.
- Period: exactly 8192 CPU cycles (1.6667 ms). The counter is clocked by
  the CPU clock, so the cycle count between NMIs is exact.
- The counter is not reset together with the CPU: the first NMI after
  power-on or reset can come at any time, including during the first
  instruction. The NMI vector must be valid and the handler safe from
  the start.
- Every NMI pushes 3 bytes (PCH, PCL, P) onto the stack page at the
  current S. Entry costs 7 cycles, `RTI` 6 cycles.
- The 65C02 clears the decimal flag on interrupt entry.

### IRQ / BRK

/IRQ is active low and tied to VSS, so IRQ is **permanently asserted**.
After reset the I flag is set; a single `CLI` causes an endless IRQ loop.

- Never execute `CLI` (or `PLP`/`RTI` with I = 0 in the pulled status).
- `$FFFE` is still reached by `BRK`; its handler must treat BRK as a
  fatal error.

### Instruction set

The GTE G65SC02 lacks the Rockwell bit instructions (`RMB`, `SMB`, `BBR`,
`BBS`) and `WAI`/`STP`. Only the common 65C02 subset may be used, so the
same image runs on all units.

ca65 setting: `--cpu 65SC02`. With cc65 2.19:

| Instruction                         | `6502` | `65SC02` | `65C02` |
|-------------------------------------|--------|----------|---------|
| `RMB0`, `SMB0`, `BBR0`, `BBS0`      | reject | reject   | accept  |
| `WAI`, `STP`                        | reject | reject   | accept  |
| `STZ`, `BRA`, `PHX`, `TRB`, `TSB`, `INC A`, `LDA (zp)`, `BIT #` | reject | accept | accept |

`make` checks that the forbidden instructions do not assemble.

## 2. Memory map

"Mirror" is the mirror mask: the register responds to every address that
differs only in the mirror bits.

| Address range | Base  | Mirror | Dir | Function |
|---------------|-------|--------|-----|----------|
| `$0000-$1FFF` | -     | -      | R/W | 8 KiB SRAM |
| `$2000-$23FF` | `$2000` | `$03FF` | W | LCD data shift register (section 3) |
| `$2400-$27FF` | `$2400` | `$03FF` | W | board LED file data (section 6) |
| `$2800-$2BFF` | `$2800` | `$03FF` | W | board rank multiplexer (section 6) |
| `$2C00-$2FFF` | `$2C00-$2C07` | `$03F8` | R | keypad, A0-A2 select key, bit 7 (section 4) |
| `$3000-$33FF` | `$3000` | `$03FF` | R | board sensor input (section 6) |
| `$3400-$37FF` | `$3400-$3407` | `$03F8` | W | 74HC259 output latch, A0-A2 select Q0-Q7, data in D7 (section 5) |
| `$3800-$3BFF` | `$3800` | `$03FF` | W | not connected |
| `$3C00-$3FFF` | -     | -      | -   | not connected |
| `$4000-$7FFF` | -     | -      | R   | opening book cartridge slot (section 7) |
| `$8000-$FFFF` | -     | -      | R   | 32 KiB ROM |

No bank switching. Vectors at `$FFFA` (NMI), `$FFFC` (RESET), `$FFFE`
(IRQ/BRK).

`$3800`: some emulators raise the next NMI only after a write to `$3800`.
MM-IV-DIAG writes it at the start of every NMI (`HW_NMI_ACK`); on the
real hardware the write has no effect.

Reading:

- The write-only registers are not readable (open bus). Keep shadow
  copies.
- Keypad reads drive only D7; bits 0-6 are open bus. Always mask with
  `$80`.
- An empty cartridge slot is open bus (section 7).

## 3. LCD display unit

One CD4011 and four CD4015 (dual 4-bit shift registers), no LCD
controller. Four 7-segment digits with decimal points and a colon.

### Data path

A write to `$2000` clocks the shift register: the new byte enters at the
leftmost digit and every digit moves one position to the right; the byte
in the rightmost digit is lost.

| Digit | Position  | Holds after four writes |
|-------|-----------|-------------------------|
| 3     | leftmost  | 4th (last) byte written |
| 2     |           | 3rd byte                |
| 1     |           | 2nd byte                |
| 0     | rightmost | 1st byte written        |

To show "dIAG", write G, A, I, d in this order. The shift register
outputs drive the segments directly (no output latch); while the four
bytes are written the display shows intermediate patterns for a few
microseconds.

### Segment bits

| Bit | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|-----|---|---|---|---|---|---|---|---|
| Segment | a (top) | b (top right) | c (bottom right) | d (bottom) | e (bottom left) | f (top left) | g (middle) | see below |

Bit 7 differs per digit:

- digits 3, 2, 1: decimal point at the bottom right of that digit
- digit 0: the colon between digit 2 and digit 1; digit 0 has no
  decimal point

### Common (backplane) and AC drive

The LCD common is driven by latch Q7. A segment is visible when its data
bit differs from Q7:

```
visible = Q7 ? ~data : data      (per bit, all four digits)
```

To show a pattern P with Q7 = c, write `P XOR (c ? $FF : $00)` to all
four digits. Keeping Q7 constant is DC drive, which damages the LCD over
time. **AC drive:** periodically toggle Q7 and rewrite all four digits
with the data inverted; every segment and the backplane then see a
square wave without DC component, and the image is unchanged.
MM-IV-DIAG does this every 5 NMIs (60 Hz AC).

Order: shift the four data bytes for the coming phase in first, then
toggle Q7.

The per-digit XOR masks `LCD_XOR_DIGIT0..3` in `include/timing.inc`
(default `$00`) invert single digits, for a display that shows a digit
inverted.

Q7 also selects the keypad bank (section 4): toggling Q7 for the AC
drive and switching banks for the key scan are the same operation and
must be coordinated in the NMI handler.

## 4. Keypad

Two banks of 8 keys, read through a 74HCT251 8-to-1 multiplexer. The
bank is selected by latch Q7 (shared with the LCD common). Reading
`$2C00 + n` (n = 0..7) returns key n of the selected bank in bit 7,
**active low** (0 = pressed).

| Address | Bank 0 (Q7 = 0) | Bank 1 (Q7 = 1) |
|---------|-----------------|-----------------|
| `$2C00` | CL              | E / 5 / Queen   |
| `$2C01` | POS             | F / 6 / King    |
| `$2C02` | MEM             | G / 7           |
| `$2C03` | INFO            | A / 1 / Pawn    |
| `$2C04` | LEV             | H / 8           |
| `$2C05` | ENT             | B / 2 / Knight  |
| `$2C06` | Right / White / 0 | C / 3 / Bishop |
| `$2C07` | Left / Black / 9  | D / 4 / Rook   |

Keys bounce; debounce in software.

Reset: the two RES buttons are wired in series to the CPU /RESET line;
reset happens only when both are pressed. They are not readable by
software. Reset affects the CPU only; latch, LCD shift register and board
latches keep their state.

## 5. Output latch 74HC259 (`$3400-$3407`)

Addressable latch: address bits A0-A2 select output Qn, data bit D7 is
the new value; D0-D6 are ignored. One write changes exactly one output.
Write `$80` for 1, `$00` for 0. The latch is not readable; keep a shadow
copy.

| Address | Output | Function |
|---------|--------|----------|
| `$3400` | Q0 | module LED, black to move |
| `$3401` | Q1 | module LED, white to move |
| `$3402` | Q2 | module LED, INFO |
| `$3403` | Q3 | module LED, MEM |
| `$3404` | Q4 | module LED, POS |
| `$3405` | Q5 | module LED, PLAY |
| `$3406` | Q6 | speaker (1 bit) |
| `$3407` | Q7 | LCD common + keypad bank select |

Q = 1 lights a module LED. The outputs are undefined after power-on;
write all eight early in boot.

### Sound

1-bit speaker on Q6, no tone generator. Tones are produced by toggling Q6
in software. A square wave with a half period of N CPU cycles has the
frequency

```
f = 4915200 / (2 * N)  Hz
```

The NMI interrupts any timing loop for its full handler duration, which
lowers the pitch and adds jitter; tone tables must account for it
(hal-api.md, "Sound").

## 6. Sensor board

Magnetic (reed) sensors under each field and one LED per field. The
Modular, Exclusive and München boards share the same interface.

| Address | Dir | Function |
|---------|-----|----------|
| `$2800` | W | rank multiplexer, bit r = 0 selects rank r+1 (active low) |
| `$2400` | W | LED file data, bit f = 1 lights file a+f in the selected ranks |
| `$3000` | R | sensors of the selected ranks, bit f = 0 means a piece on file a+f (active low) |

Mux bit r is rank r+1 (bit 0 = rank 1, white's back rank), data bit f is
file a+f (bit 0 = file a).

### Sensors

With one rank selected, a 0 bit is a piece on that field; with no rank
selected the read is `$FF`; with several ranks selected the result is the
AND (piece on that file in any selected rank). Full scan: select each
rank in turn (mux = ~(1 << r)), read `$3000`. Reed contacts bounce;
debounce in software.

### LEDs

The 64 field LEDs form an 8 x 8 matrix driven by the same rank
multiplexer: a LED is lit when its rank is selected in `$2800` (bit = 0)
and its file bit is 1 in `$2400`. Fields in different ranks can only be
lit at the same time by multiplexing: cycle through the ranks
continuously, writing each rank's LED pattern while that rank is
selected. With 8 ranks each LED is on for at most 1/8 of the time.

Since the multiplexer is shared, every sensor scan step lights the
selected rank with the current LED data; LED refresh and sensor scan are
done together, one rank per step. To avoid ghosting, clear the LED data
before switching the rank, then select the rank, then write the new
data.

Mux and LED data are undefined after power-on; initialise them early
(mux `$FF` = no rank, LED data `$00`).

## 7. Cartridge slot (`$4000-$7FFF`)

Read-only slot for the opening book cartridges:

| Module | Cartridge | Size | CRC-32 | SHA1 |
|--------|-----------|------|--------|------|
| MM IV | HG 440 Opening Library | 16 KiB | `81ffcdfd` | `b0f7bcc11d1e821daf92cde31e3446c8be0bbe19` |
| MM V | HG 550 Opening Library | 16 KiB | `0359f13d` | `833cef8302ad8d283d3f95b1d325353c7e3b8614` |

**No identifier.** Neither cartridge has a header, signature, ASCII text
or fill area: all 16384 bytes are opening book data from `$4000` on.
Known cartridges are identified by the CRC-32 over `$4000-$7FFF`.

An empty slot is open bus: a read typically returns the last value on
the data bus, which for `LDA abs,X` / `LDA (zp),Y` is the high byte of
the address just fetched (`$40`-`$7F`). Presence detection must not rely
on a single value.

**Presence (plausibility rule)**, evaluated per 256-byte page of the
slot:

| Property | HG 440 | HG 550 | Empty slot |
|----------|--------|--------|------------|
| distinct values per page, minimum | 73 | 18 | about 1 |
| bytes equal to the address high byte, max per page | 7 | 11 | up to 256 |

A cartridge is present when two read passes are identical and every
page has at least 8 distinct values and at most 64 bytes equal to its
address high byte (`CART_MIN_DISTINCT`, `CART_MAX_ADDRHI` in
`include/timing.inc`). Known CRCs are reported by name, other content as
an unknown cartridge with its CRC.

## 8. Reset and power-on

- /RESET from the power-on circuit and from the two RES buttons in
  series.
- After reset: I = 1, S undefined. The CMOS CPUs clear D on reset; boot
  code executes `CLD` anyway.
- RAM content is undefined.
- NMIs start immediately (section 1).
- All output registers (latch, LCD, board mux, LED data) are undefined
  and must be initialised by software.
