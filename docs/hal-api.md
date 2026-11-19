# HAL API

The hardware abstraction layer (`hal/`, built as `build/hal.lib`) and the
runtime (`runtime/`) are everything an application needs to drive the
MM IV / MM V hardware: display, keys, sound, sensor board with LEDs,
module LEDs, time base and cartridge slot. The diagnostic application
(`diag/`) uses only this API; an engine project keeps `runtime/`, `hal/`,
`include/` and `cfg/` and replaces `diag/`.

Hardware background: [hardware.md](hardware.md). Boot sequence:
[boot.md](boot.md). Tuning constants: `include/timing.inc`. API
declarations: `include/hal.inc`.

## Calling convention

- Parameters in A, X, Y. Pointer parameters in the fixed zero-page
  registers `hal_p0` (`$18-$19`) and `hal_p1` (`$1A-$1B`).
- Results in A (and X), or a flag in C (C = 1 means "yes" or "event
  available").
- Each routine lists the registers it clobbers; registers not listed are
  preserved. Flags (except a documented C result) are always clobbered.
- Decimal mode must be off (it always is; nothing in the ROM sets it).
- All routines are called from the foreground with the NMI handler
  running. None may be called from the NMI handler, and none may be
  interrupted by itself (the HAL is not re-entrant; the NMI parts only
  use their own state).
- `JSR` depth: at most 2 levels inside the HAL.
- Never execute `CLI` (the IRQ line is tied low, hardware.md section 1).

## Memory map for applications

| Range | Owner | Contents |
|-------|-------|----------|
| `$00-$17` | runtime | fixed addresses, `include/runtime.inc` (boot.md) |
| `$18-$1B` | HAL | pointer registers `hal_p0`, `hal_p1` (fixed) |
| `$1C-$37` | HAL | HAL variables (linker segment `HALZP`, 24 of 28 bytes used) |
| `$38-$FF` | application | linker segment `ZEROPAGE` (200 bytes) |
| `$0100-$01FF` | CPU | stack; an NMI uses up to 10 bytes on top of the interrupted code |
| `$0200-$02FF` | runtime, HAL | `RTBSS`, `HALBSS` (133 bytes used) |
| `$0300-$1FFF` | application | linker segment `BSS` (7.25 KiB); the diagnostic keeps all its variables in the zero page, so its test 6 can test this range destructively |
| `$4000-$7FFF` | cartridge | opening library, read only |
| `$8000-$807F` | ROM | ident block (below, `include/ident.inc`) |
| `$8080-$FFF9` | ROM | `CODE`, `RODATA` |
| `$FFFA-$FFFF` | ROM | vectors NMI, RESET, IRQ/BRK |

The runtime clears all RAM except the stack before `main` is entered.
Exact addresses of all symbols: `build/mm-iv-diag-<version>.map` and
`.lbl`.

## ROM identification block

At `$8000`, 128 bytes (`include/ident.inc`, written by `runtime/ident.s`,
CRCs patched after linking by `tools/romtool.pl`). Format version 3:

| Offset | Size | Contents |
|--------|------|----------|
| `$00` | 16 | `"MM-IV-DIAG"`, NUL padded (an engine puts its own name here) |
| `$10` | 1 | format version (3) |
| `$11` | 3 | version major, minor, patch (binary) |
| `$14` | 12 | version string, NUL padded (from the `VERSION` file) |
| `$20` | 16 | contact e-mail address `"mm4@strcmp.org"`, NUL padded (at least one NUL) |
| `$30` | 20 | build timestamp UTC `"YYYY-MM-DD HH:MM:SS"`, NUL: the release date from the `RELEASE_DATE` file, not the time of the build, so every build of a release is identical |
| `$44` | 4 | CRC-32 of the whole image (`$8000-$FFFF`), little endian |
| `$48` | 32 | 8 x CRC-32 of the 4 KiB blocks `$8000 + n * $1000`, little endian |
| `$68` | 24 | unused, `$FF` |

All CRCs (IEEE 802.3, as zip) are computed with the CRC area
`$8044-$8067` taken as zero. `romtool.pl verify` checks all of them,
`romtool.pl info` prints the block. The diagnostic checks the ROM with
the block CRCs (`diag/romchk.s`), which also locates a fault.

## Runtime services

| Symbol | Kind | Description |
|--------|------|-------------|
| `main` | entry | The application provides `main`; the runtime jumps to it after the power-on tests with `S = $FF`, I = 1, D = 0, RAM cleared, display showing `app_banner`, NMI handler running. `main` never returns. |
| `app_banner` | data | The application provides 4 bytes of raw segments (index 0 = rightmost digit) shown from reset on. |
| `rt_ticks` | `$02-$05` | 600 Hz tick counter, 32 bit, little endian. Read with `tmr_read`. |
| `rt_fatal` | routine | A = error code (`RT_E_*`), `rt_err_word`, `rt_err_data` set: stops the HAL and shows the error forever (codes.md). Never returns. Applications may define their own codes from `$10` on. |
| `rt_hexfont` | data | 16 bytes: 7-segment patterns of `0-9 A b C d E F`. |
| `rt_march_u` | routine | March U RAM test (runtime/memtest.s): A = first page, X = last page, Y = background; C = 1 on error with `rt_err_word` = address, `rt_err_data` = failing bits. Destroys the content of the pages. |

## NMI handler

`runtime/nmi.s` (600 Hz, cannot be disabled) increments `rt_ticks` and
calls `hal_nmi` (`hal/hal.s`). The work is split over the ticks so that
key events and board events never fall into the same tick:

| Tick | Work |
|------|------|
| 4 of 5 (`LCD_AC_TICKS` = 5) | `brd_nmi`: sensors of the rank selected since the last tick (debounce, events), then LEDs of the next rank |
| every 5th | `brd_nmi_leds`: LEDs of the next rank only; `key_nmi`: keys of the bank selected by Q7 (debounce, events); `disp_nmi`: rewrite the LCD inverted, then toggle Q7 (LCD common, keypad bank) |

Consequences: LCD AC drive at 60 Hz, each keypad bank sampled at 60 Hz,
each board rank lit 1/8 of the time and scanned at 75 Hz (every 5th scan
of a rank is skipped on a key tick, which only delays its debounce).

### Cycle budget (measured)

Measured for every NMI from the interrupt sequence to the end of `RTI`
(7 + body + 6 cycles).
 Budget: 15 % of the 8192 cycles between NMIs = 1228 cycles.

| Load | Samples | min | avg | max | max % of 8192 |
|------|---------|-----|-----|-----|---------------|
| idle (no keys, no board changes) | 600 | 161 | 199.8 | 355 | 4.3 % |
| stress: all 16 keys pressed and released at once, 32 pieces removed and restored (8 changes per rank), 22 LEDs blinking | 588 | 161 | 209.8 | 831 | 10.1 % |

The stress run covers the worst case of each tick type: 8 key events
(one bank) on a key tick, 8 board events (one rank) on a board tick. The
foreground keeps at least 90 % of the CPU in every NMI period and 97.4 %
on average.

The figures include the `stz $3800` at the start of every NMI
(4 cycles, hardware.md section 2).

## Display (`hal/display.s`)

The display buffer `disp_buf` (4 bytes, zero page, index 0 = rightmost
digit) holds logical segment patterns: bit 0-6 = segments a-g, bit 7 =
decimal point of digits 3..1, or the colon for digit 0 (hardware.md,
section 3). The NMI writes it to the LCD at every common toggle, so a
change is visible within 8.3 ms. Writing `disp_buf` directly is allowed.

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `disp_init` | `disp_buf` = initial content | - | A |
| `disp_clear` | - | all segments off | A |
| `disp_fill` | A = pattern | all four digits = A (`$FF` = every segment incl. DP and colon) | - |
| `disp_raw` | A = segments, X = digit (0 = right) | | - |
| `disp_set4` | `hal_p0` = 4 bytes, index 0 = rightmost | | A, Y |
| `disp_hex8` | A = value, X = digit of the low nibble (0..2) | two hex digits at X+1, X | A, Y |
| `disp_hex16` | A = low, X = high | four hex digits | A, X, Y |
| `disp_dec` | A = low, X = high (0..9999) | right aligned, leading zeros blank; > 9999 shows `----` | A, X, Y |
| `disp_str` | `hal_p0` = NUL-terminated ASCII | 7-segment text, right aligned (below) | A, X, Y, `hal_p1` |
| `disp_str_to` | as `disp_str`, `hal_p1` = 4-byte target buffer | text rendered into the buffer instead of the display | A, X, Y |
| `disp_lock` | - | starts an atomic update: `disp_hold` += 1, the NMI postpones the LCD refresh | - |
| `disp_unlock` | - | ends it: `disp_hold` -= 1 | - |

Atomic updates: `disp_dec`, `disp_str`, `disp_str_to`, `disp_hex16`,
`disp_set4` and `disp_fill` lock internally, so the LCD never shows a
half-built buffer. Wrap your own multi-step writes to `disp_buf` in
`disp_lock`/`disp_unlock` (they nest; keep the section to a few hundred
cycles and never wait inside it). While `disp_hold` is non-zero `hal_nmi`
treats the common-toggle tick as a plain board tick and retries on the
next tick, so the refresh is late by 1.67 ms per tick held.

`disp_str` details: characters `$20-$7F` use the font `disp_font`
(others blank). `.` sets the decimal point of the character before it
(digits 3..1; ignored after the rightmost character). `:` lights the
colon and takes no digit. Only the last four characters are shown.
Example: `"0.1.0"` → ` 0.1.0`, `"12:34"` → `12:34`, `"E-03"` → `E-03`.
Letters without a 7-segment form share glyphs: K/X = H, M/N/W = n, V = u,
O = 0, S = 5, Z = 2. Upper and lower case differ for b/B, c/C, h/H, o/O,
u/U, i/I.

`disp_nmi` (NMI only): writes all digits as
`buf XOR phase XOR LCD_XOR_DIGITn` for the new phase, then toggles Q7
(data before common, hardware.md section 3).

## Keys (`hal/keys.s`)

Key codes (`include/hal.inc`), code = 8 * bank + address offset:

| Code | Key | Code | Key |
|------|-----|------|-----|
| `$00` `KEY_CL` | CL | `$08` `KEY_E5` | E / 5 / Queen |
| `$01` `KEY_POS` | POS | `$09` `KEY_F6` | F / 6 / King |
| `$02` `KEY_MEM` | MEM | `$0A` `KEY_G7` | G / 7 |
| `$03` `KEY_INFO` | INFO | `$0B` `KEY_A1` | A / 1 / Pawn |
| `$04` `KEY_LEV` | LEV | `$0C` `KEY_H8` | H / 8 |
| `$05` `KEY_ENT` | ENT | `$0D` `KEY_B2` | B / 2 / Knight |
| `$06` `KEY_RIGHT` | Right / White / 0 | `$0E` `KEY_C3` | C / 3 / Bishop |
| `$07` `KEY_LEFT` | Left / Black / 9 | `$0F` `KEY_D4` | D / 4 / Rook |

Scanning and debounce run in the NMI: a bank's 8-bit sample is accepted
after `KEY_DEBOUNCE` (2) further equal samples, 33-50 ms after the
change. Presses shorter than one sample period (17 ms) are ignored.
Every accepted change of a key is queued as an event: the key code, bit 7
(`KEY_RELEASED`) set for a release. The queue holds 7 events; further
events are dropped until the application reads. The reset buttons are
not readable (hardware reset).

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `key_get` | - | C = 1: A = event; C = 0: none | A, X |
| `key_down` | A = key code | C = 1 pressed (debounced) | A, X, Y |
| `key_flush` | - | pending events discarded | A |
| `key_init` | - | state and queue cleared (called by `hal_init`) | A |

## Sensor board and module LEDs (`hal/board.s`)

Field number = 8 * rank_index + file_index: a1 = 0, h1 = 7, a8 = 56,
h8 = 63. Bitmaps of 8 bytes: byte = rank index, bit = file index.

| Data | Description |
|------|-------------|
| `brd_state` | debounced sensors, 1 = piece (read only for the application) |
| `brd_led` | field LEDs, 1 = on (may be written directly) |
| `brd_blink` | 1 = LED blinks (only with the `brd_led` bit set; may be written directly) |

Sensors are debounced per rank: a rank's sample is accepted after
`BRD_DEBOUNCE` (3) further equal scans, 40-60 ms after the change. The
first accepted sample of each rank after reset sets the state without
events (the pieces standing on the board at power-on are not reported).
Every later change of a field is queued: field number, bit 7
(`BRD_PLACED`) set when a piece was placed, clear when it was lifted.
The queue holds 31 events (a full board clear is 32).

LEDs are multiplexed by rank (1/8 duty); any combination of fields can be
lit. Blinking LEDs change phase every `BRD_BLINK_TICKS` (150 ticks, 2 Hz).

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `brd_get` | - | C = 1: A = event; C = 0: none | A, X |
| `brd_flush` | - | pending events discarded | A |
| `brd_piece` | A = field | C = 1 piece present | A, X, Y |
| `brd_led_set` | A = field | LED on, steady | A, X, Y |
| `brd_led_blink` | A = field | LED blinking | A, X, Y |
| `brd_led_clear` | A = field | LED off | A, X, Y |
| `brd_led_all` | - | all 64 LEDs on, steady | A, X |
| `brd_led_alloff` | - | all LEDs off | A, X |
| `mled_set` | A = bits 0-5: module LED Q0-Q5 on | latch written | A, X |
| `mled_get` | - | A = module LED state | - |
| `brd_init` | - | all cleared (called by `hal_init`) | A, X |

Module LEDs (layout labels, hardware.md section 5): Q0 black to move,
Q1 white to move, Q2 INFO, Q3 MEM, Q4 POS, Q5 PLAY.

## Sound (`hal/sound.s`)

1-bit speaker on Q6. `snd_tone` toggles Q6 in a timed loop and blocks
for the duration; the NMI keeps running.

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `snd_tone` | X, Y = loop count (`SND_LDXY f`), A = duration in 10 ms units (1..255; 0 = return at once) | speaker off | A, X, Y |
| `snd_beep_ok` | - | 2000 Hz, 60 ms | A, X, Y |
| `snd_beep_err` | - | 300 Hz 250 ms, 100 ms pause, 300 Hz 250 ms | A, X, Y |
| `snd_click` | - | 3000 Hz, 20 ms | A, X, Y |

Frequency: one half period of the loop takes `C = 5 N + 4 hi + 61`
cycles (N = loop count, hi = (N - 1) >> 8), so without NMIs
`f = 4915200 / (2 C)`. The NMI handler adds on average `SND_NMI_AVG`
(199) cycles per 8192, lowering the pitch by 2.4 %; the macros
`SND_LDXY f` (code) and `SND_BYTES f` (tables) in `include/timing.inc`
compute N for a frequency in Hz including this correction. Range about
100 Hz to 20 kHz.
A half period that contains an
NMI is longer by the handler time (about 40 µs), heard as slight
roughness at high frequencies. Duration is counted in ticks, accurate to
1/600 s.

## Timer (`hal/timer.s`)

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `tmr_read` | - | A = ticks bits 0-7, X = bits 8-15 (consistent read) | - |
| `tmr_wait` | A = low, X = high: n ticks (0..32767) | returns after (n - 1)..n tick periods | A, X |

`MS_TICKS(ms)` (`include/timing.inc`) converts milliseconds to ticks.
Elapsed time: subtract two `tmr_read` values (16-bit, wraps after
109 s); compare signed for timeouts.

## CRC-32 (`hal/crc.s`)

CRC-32 as zip uses it (IEEE 802.3, reflected, init and final XOR
`$FFFFFFFF`), table driven (4 x 256 bytes ROM, computed at assembly
time), about 60 cycles per byte.

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `crc_init` | - | `crc_val` = `$FFFFFFFF` | A |
| `crc_byte` | A = byte | `crc_val` updated | A, X |
| `crc_block` | `hal_p0` = start, `hal_p1` = length (0 = none) | `crc_val` updated, `hal_p0` = end + 1, `hal_p1` = 0 | A, X |
| `crc_final` | - | `crc_val` = CRC-32, little endian | A, X |

`crc_val` is a 4-byte zero-page variable. The ROM image CRC in the ident
block is the CRC over `$8000-$FFFF` with the 4 CRC bytes taken as zero
(boot.md).

## Cartridge (`hal/cart.s`)

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `cart_check` | - | A = `CART_NONE` (0), `CART_UNKNOWN` (1), `CART_HG440` (2), `CART_HG550` (3); `crc_val` = CRC-32 of `$4000-$7FFF` | A, X, Y, `hal_p0`, `hal_p1` |

Takes about 1 s. Presence is decided by the plausibility rule of
hardware.md section 7: two CRC passes must agree, every page must have
at least `CART_MIN_DISTINCT` (8) distinct values and at most
`CART_MAX_ADDRHI` (64) bytes equal to its address high byte. Known
cartridges are identified by their CRC-32 (`81ffcdfd` HG 440,
`0359f13d` HG 550).

## Initialisation (`hal/hal.s`)

| Routine | In | Out | Clobbers |
|---------|----|-----|----------|
| `hal_init` | zero page and page 2 cleared, `disp_buf` = initial content | speaker and module LEDs off, keys and board initialised, LCD drive started; called by the runtime before the NMI handler is enabled | A, X, Y |
| `hal_nmi` | NMI only | see "NMI handler" | A, X, Y |

## Tuning constants (`include/timing.inc`)

| Constant | Value | Meaning |
|----------|-------|---------|
| `LCD_XOR_DIGIT0..3` | `$00` | per-digit inversion (hardware.md section 3) |
| `LCD_AC_TICKS` | 5 | ticks per LCD half period: 60 Hz AC, keys sampled at 60 Hz per bank |
| `KEY_DEBOUNCE` | 2 | equal samples to accept a key change |
| `BRD_DEBOUNCE` | 3 | equal scans to accept a rank change |
| `BRD_BLINK_TICKS` | 150 | LED blink half period (2 Hz) |
| `SND_DUR_TICKS` | 6 | duration unit of `snd_tone` (10 ms) |
| `SND_NMI_AVG` | 199 | NMI cycles per period for the pitch correction |
| `SND_*_FREQ`, `SND_*_DUR`, `SND_ERR_GAP` | | standard beeps |
| `CART_MIN_DISTINCT`, `CART_MAX_ADDRHI` | 8, 64 | cartridge plausibility rule |
| `FATAL_*` | | fatal error and pre-RAM failure loops (boot.md) |
| `IDLE_*` | | idle display of the diagnostic application |

## Writing an application

1. Provide `main` and `app_banner` (see `diag/main.s`); link with
   `runtime/*.o` and `build/hal.lib` using `cfg/rom.cfg`. The linker takes
   only the HAL modules the application references.
2. Use `ZEROPAGE` (`$38-$FF`) and `BSS` (`$0300-$1FFF`) for variables.
   Put the program name and your contact address into the ident block
   (`runtime/ident.s`; the name also in `$MAGIC` in `tools/romtool.pl`).
3. Poll `key_get` and `brd_get` in the main loop; use `tmr_read` for
   timeouts. Keep the display alive (the user should always see that the
   unit works).
4. Report unrecoverable errors with `rt_fatal`.
