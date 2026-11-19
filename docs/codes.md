# Display codes and beep patterns

The display has four digits; "digit 3" is the leftmost. Hex digits are
shown as `0-9 A b C d E F`.

## Power-on

| Display | Time | Meaning |
|---------|------|---------|
| `dIAG` | ~0.9 s | banner from reset on: RAM tests (runtime), then ROM check (block CRCs) |
| ` 1.0.0` | 1 s | version |
| `PA55` | 1 s | all power-on tests passed, confirm beep; then the menu |
| `E-03` | 1 s | ROM check failed, error beep; then the menu, whose idle display also shows `E-03` and `b-mm` (below) |

Failures of the RAM tests stop the boot with the codes below
(pre-RAM failures, fatal errors). A ROM error does not stop it: with a
ROM emulator or EEPROM the fault may be intermittent, and the tests stay
usable.

## Menu and idle display (sign of life)

While no test runs, the display alternates every 5 s between `dIAG` and
the version (e.g. ` 1.0.0`); after a ROM error at power-on also `E-03`
and `b-mm`. In between, a wipe lights all segments
digit by digit from left to right (including decimal points and colon),
holds them for 0.25 s, then reveals the next screen from left to right.
The wipe doubles as a quick segment check. A frozen display means the
program has stopped. Timing: `IDLE_*` in `include/timing.inc`.

Keys in the menu: `1`-`8` (A/1 ... H/8) start a test, `9` (Left / 9)
starts the combined countdown and melody test (title `t-9`), any other key clicks. In a test, `CL`
returns to the menu. A test starts with its title
`t-n` for 0.7 s.

Pause: in tests 1, 2 and 4-9, key `0` (Right / 0) freezes the test with a
confirm beep: display, field LEDs and module LEDs keep their state, so a
faulty segment or LED can be watched while tapping or pressing on the
unit. `0` again resumes the test where it stopped (click), `CL` returns
to the menu, other keys click. A paused test shows no sign of life on
purpose (a blinking colon stays as it was). In the key test (3), `0`
shows its code instead, and `CL` shows its code too: hold `CL` for 1 s
to leave (`DIAG_CL_HOLD_TICKS`).

A blinking colon (heartbeat, 1 Hz) means a test is running and waiting;
it blinks over the other characters.

## Tests

| Key | Test | Display |
|-----|------|---------|
| 1 | display | all segments on (5 s); each digit fully on, left to right (0.5 s each); each segment line on all digits: a, b, c, d, e, f, g, decimal points + colon (0.4 s each); all off (0.5 s); repeats |
| 2 | sound | C major scale C5-C6 (523 ... 1047 Hz, 0.3 s each), the frequency in Hz on the display; 1 s pause; repeats |
| 3 | keys | `c---` waiting; each key shows `c-hh`, hh = key code (table below), with a click; `CL` too (`c-00`), hold `CL` for 1 s to return to the menu |
| 4 | LEDs | running light a1, b1 ... h8, the square on the display (`  E4`, 80 ms each); module LEDs Q0-Q5 one by one, `L-00` ... `L-05` (0.3 s each); all 64 fields and 6 module LEDs on, ` ALL` (5 s); repeats |
| 5 | sensors | every field LED shows its sensor (piece = lit); `P nn` number of pieces at the start; each change: `P-E4` piece placed on e4, `L-E4` piece lifted from e4, with a click |
| 6 | RAM + ROM loop | see below |
| 7 | cartridge | `----` while checking (1 s); `nonE` no cartridge, ` 440` HG 440, ` 550` HG 550, `CArt` unknown cartridge, each followed by its CRC-32 over `$4000-$7FFF` in two screens (high word, low word, e.g. `81FF` `CdFd`); repeats |
| 8 | info | version (` 1.0.0`), build date UTC: year (`2026`), month.day (`11.01`), hours:minutes (`14:05`), ` Crc` and the ROM CRC-32 of the ident block (high word, low word); repeats |
| 9 | smiley, countdown + melody (combined board LED and sound test) | a smiley on the 8x8 field LEDs for 3 s that winks once after 1 s (right eye closed for 0.4 s), display blank; then a countdown on the 8x8 field LEDs: digits 9 ... 0 in a bold 8x8 font (2-pixel strokes), one per second with a ping (1760 Hz, 80 ms), the digit also on the display (`   9`); then Beethoven's "Ode to Joy" (16 bars, C major, G4-G5, quarter = 150 bpm): each note shows its frequency in Hz and a bar on files d/e whose height follows the pitch; back to the menu after 1.5 s. `EGG_*` in `include/timing.inc` |

Key codes (test 3, `include/hal.inc`):

| Code | Key | Code | Key |
|------|-----|------|-----|
| `00` | CL (held 1 s: leaves the test) | `08` | E / 5 |
| `01` | POS | `09` | F / 6 |
| `02` | MEM | `0A` | G / 7 |
| `03` | INFO | `0b` | A / 1 |
| `04` | LEV | `0C` | H / 8 |
| `05` | ENT | `0d` | B / 2 |
| `06` | Right / 0 (pauses the other tests) | `0E` | C / 3 |
| `07` | Left / 9 | `0F` | D / 4 |

### Test 6: RAM and ROM loop

Each pass (about 1.3 s): page 2 (March U, HAL paused for 32 ms),
`$0300-$1FFF` (March U, backgrounds `$00` and `$55`), ROM (CRC-32 of
the eight 4 KiB blocks). Errors are counted and the loop goes on; every
new error sounds the error beep. Screens, 1 s each, cycling:

| Screen | Shown | Meaning |
|--------|-------|---------|
| `Pnnn` | always | passes completed (counts to 9999, then 0) |
| `E-01` | after a RAM error | RAM data error |
| `aaaa` | after a RAM error | address of the last RAM error |
| `b-bb` | after a RAM error | failing bits of the last RAM error |
| `cnnn` | after a RAM error | number of RAM errors |
| `E-03` | after a ROM error | ROM checksum error |
| `b-mm` | after a ROM error | bad block mask of the last ROM error |
| `cnnn` | after a ROM error | number of ROM errors |

The zero page and the stack page hold the running program and are tested
at power-on only.

### ROM block mask `b-mm`

Bit n set = the 4 KiB block `$8000 + n * $1000` has the wrong CRC-32
(block CRCs in the ident block, docs/hal-api.md). How to read it:

| Mask | Likely cause |
|------|--------------|
| one bit | wrong or damaged content in that block (programming, a bad cell) |
| `AA` or `55` (odd or even blocks) | A12 stuck (open, shorted) |
| `CC` or `33` | A13 |
| `F0` or `0F` | A14 |
| `FF` | data line, access time too slow, wrong image |

A ROM that is wrong where the program runs may crash the diagnostic
instead of reporting `E-03` (the ROM checks itself); a frozen display
then points to the ROM.

## Beeps

| Sound | Meaning |
|-------|---------|
| 2000 Hz, 60 ms | confirm: power-on tests passed, action accepted, test paused (key `0`) |
| 3000 Hz, 20 ms | key click |
| 300 Hz 250 ms, pause 100 ms, 300 Hz 250 ms | error |
| ~950 Hz buzz in every second LCD half period | pre-RAM failure (below) |
| ~950 Hz, 0.3 s, once per screen cycle | fatal error (below) |

## Pre-RAM failures (no RAM used, see boot.md)

Shown permanently with a buzz (about 950 Hz tone in every second LCD
half period).

| Display | Meaning |
|---------|---------|
| `aa.bb` | zero page fault at `$00aa`, bb = failing bits (read XOR expected) |
| `aa:bb` | stack page fault at `$01aa`, bb = failing bits |

Example: `42.08` = bit 3 of `$0042` is faulty, `F0:20` = bit 5 of `$01F0`.
A failing data bit that shows up at many addresses points to the data
line D(n) or the RAM chip; a fault at a single address points to the chip.

## Fatal errors (runtime/fatal.s)

Repeating cycle of up to three screens, about 1 s each, with an error
tone (about 950 Hz, 0.3 s) at the start of the first screen.

| Code | Screen 1 | Screen 2 | Screen 3 | Meaning |
|------|----------|----------|----------|---------|
| E-01 | `E-01` | address | `b-bb` failing bits | RAM data error (March U), `$0200-$1FFF` |
| E-02 | `E-02` | address | `r-vv` value read | RAM address line error: the cell at this address reads another cell's value. Address `1<<n` → line A(n); value `$11+m` → it reads the cell of line A(m), `$10` → the cell `$0000` |
| E-04 | `E-04` | PC | - | unexpected IRQ (only possible after CLI, never executed by this code) |
| E-05 | `E-05` | address | - | BRK instruction executed at this address (software fault) |

E-03 (ROM checksum) is not fatal; see "Power-on" and test 6.
