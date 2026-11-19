# Power-on sequence and early boot

Code: `runtime/reset.s`, `runtime/memtest.s`, `runtime/nmi.s`,
`runtime/fatal.s`. Error displays: [codes.md](codes.md). Hardware
background: [hardware.md](hardware.md), sections 1, 2 and 8.

## Sequence

| Step | What | RAM used | NMI handler | Time |
|------|------|----------|-------------|-------------|
| 1 | `SEI`, `CLD`, `S = $FF`; latch Q0-Q7 = 0, board mux `$FF` (no rank), LED data 0; banner (`app_banner`) written to the LCD with Q7 = 0 | none | early exit | µs |
| 2 | pre-RAM March U of the zero page and the stack page, backgrounds `$00` and `$55` | none (registers only) | early exit | ~20 ms |
| 3a | address-line test A0-A12 | ZP, stack | early exit | µs |
| 3b | March U of page 2 (runtime/HAL buffers), backgrounds `$00`, `$55` | ZP, stack | early exit | ~16 ms |
| 3c | clear zero page and page 2, `disp_buf` = banner, `hal_init` (display, keys, board, module LEDs, speaker), store `NMI_MAGIC1`, then `NMI_MAGIC0` | | **on** from here | |
| 3d | March U of `$0300-$1FFF`, backgrounds `$00`, `$55`; clear `$0300-$1FFF` | | on (LCD, keys, board) | ~0.45 s |
| 4 | `JMP main` (application): ROM check, CRC-32 of the eight 4 KiB blocks against the ident block (`diag/romchk.s`) | | on | ~0.4 s |
| 5 | version (1 s), then `PASS` with confirm beep, or `E-03` with error beep (not fatal); menu | | on | 2 s |

Reset to `main` takes about 0.5 s, to the `PASS` screen about 1.9 s.
The banner is visible from the first microseconds; during steps 1-3b
(about 40 ms) the LCD is driven DC, which is harmless at that length.

The ROM check (steps 4-5) is part of the application, not of the
runtime; a ROM error is reported but does not stop the unit (codes.md).

## NMI during early boot

The NMI runs from power-on and cannot be masked (hardware.md, section 1).
The handler (`runtime/nmi.s`) starts with

```
nmi:  stz $3800          ; HW_NMI_ACK (hardware.md, section 2)
      pha
      lda nmi_magic        ; $00
      cmp #NMI_MAGIC0      ; $4D
      bne nmi_early
      lda nmi_magic+1      ; $01
      cmp #NMI_MAGIC1      ; $B2
      bne nmi_early
      ...                  ; full handler
nmi_early:
      pla
      rti
```

- It reads only `$00/$01` and writes only `$3800` (no RAM) and the
  stack: 3 bytes by the CPU (PCH, PCL, P) and 1 by `PHA`, i.e. `S`,
  `S-1`, `S-2`, `S-3`.
- The `$3800` write is first and also happens in the early exit: some
  emulators raise the next NMI only after it (hardware.md, section 2).
- Early exit costs 32 cycles (39 if the first byte matches), including
  the 7-cycle interrupt sequence and `RTI`.
- The magic values `$4D/$B2` are never written by the boot tests
  (March backgrounds `$00/$FF/$55/$AA`, address-line values `$10-$1D`,
  clearing `$00`), so a test pattern cannot start the full handler on
  half-initialised state. A RAM fault that happens to produce exactly
  `$4D/$B2` at `$00/$01` is not excluded but has a probability of
  about 1/65536 per fault pattern.
- The magic is stored second byte first, so the handler never sees a
  valid first byte with a stale second byte on the way in.
- `rt_fatal` clears `nmi_magic` first, so the HAL stops before the error
  display takes over the hardware.

## Pre-RAM test (step 2)

Model: the Apple II "Dead Test" ROM idea of testing the memory the
CPU itself needs without using it. The test is a macro (`PRE_MARCH`)
expanded for each page, half and background: only `A` and `X`, absolute
indexed addressing (`lda $0000,x` / `lda $0100,x`), immediate test values,
no `JSR`, no stack, no RAM variables.

Algorithm: March U (van de Goor), 13 operations per byte,

```
{ ⇕(w0); ⇑(r0,w1,r1,w0); ⇑(r0,w1); ⇓(r1,w0,r0,w1); ⇓(r1,w0) }
```

with 0 = background, 1 = its complement, run with backgrounds `$00`
(`$00/$FF`) and `$55` (`$55/$AA`, adjacent-bit coupling within a byte).
March U detects stuck-at, transition, address decoder (aliasing inside
the tested range) and the common coupling faults.

### Stack page and NMI pushes

Every NMI writes 4 bytes below `S`. The stack page is therefore tested
in two halves, with `S` pointing into the other half:

| Pass | `S` | NMI writes | Tested |
|------|-----|------------|--------|
| A | `$FF` | `$01FC-$01FF` | `$0100-$017F` |
| B | `$7F` | `$017C-$017F` | `$0180-$01FF` |

Limitation: during pass A the CPU relies on `$01FC-$01FF` (written by
the NMI, read back by `PLA`/`RTI`) before that area is tested in pass B.
A fault there can crash the boot before it is reported (symptom: banner
stays, no error display, no tone). The same holds for the zero page
cells `$00/$01` read by the early NMI handler, which is harmless (reads
only).

### Failure report without RAM

On a failure `X` = address low byte and `Y` = failing bits (value read
XOR expected). The failure loop (`prefail_zp` / `prefail_stack`) uses
only these registers and `A`:

- display "aa.bb" (zero page, decimal point after digit 2) or "aa:bb"
  (stack page, colon), aa = address low byte, bb = failing bits, hex;
- AC drive by busy waiting (`FATAL_DELAY_OUTER`, about 8.3 ms per half
  period, 60 Hz), digits converted with 256-entry tables
  (`rt_prefont_lo/hi`) so a single indexed load per digit suffices;
- tone: Q6 toggled at about 950 Hz during every second half period,
  heard as a buzz.

## Address-line test (step 3a)

Writes `$11 + n` to `1 << n` for n = 0..12 (`$0001 ... $1000`), then
`$10` to `$0000`, and reads all 14 cells back in the same order. An open
or shorted address line makes two cells alias, so one of them reads the
other's value. The first wrong cell is reported as E-02 with its address
and the value read (codes.md). An alias inside the zero page or stack
page is already caught by the pre-RAM test.

## RAM test (steps 3b, 3d)

`rt_march_u` (`runtime/memtest.s`): March U over whole pages with a
zero-page pointer, about 150 cycles per byte. Page 2 is tested before the
HAL starts because it holds HAL buffers; `$0300-$1FFF` is tested with the
NMI handler running (it only touches the zero page, page 2 and the
stack). Failures: E-01 (codes.md).

## Fatal errors

`rt_fatal` (A = code, `rt_err_word`, `rt_err_data`) clears `nmi_magic`,
resets `S` and loops forever over up to three screens of about 1 s with
busy-wait AC drive and an error tone at the start of each cycle. It
needs a working zero page and stack, nothing else.

IRQ/BRK (`irq` in `runtime/nmi.s`): the IRQ line is permanently asserted
(hardware.md, section 1), so returning would re-enter immediately. The
handler reads the pushed P and PC: B set → E-05 with the address of the
`BRK`, else E-04 with the interrupted PC.

## Runtime zero page

Fixed addresses (`include/runtime.inc`), because the address-line test
writes `$00, $01, $02, $04, $08, $10` before they are initialised:

| Address | Name | Use |
|---------|------|-----|
| `$00-$01` | `nmi_magic` | `$4D $B2` = full NMI handler active |
| `$02-$05` | `rt_ticks` | 600 Hz tick counter, 32 bit, little endian |
| `$06-$07` | `rt_mt_ptr` | memory test pointer |
| `$08-$0B` | `rt_mt_*` | memory test: first/last page, background, complement |
| `$0C-$0D` | `rt_err_word` | fatal error value |
| `$0E` | `rt_err_data` | fatal error data byte |
| `$0F` | `rt_err_code` | fatal error code |
| `$10-$16` | `rt_f_*` | fatal error display state |
| `$17` | - | reserved |

`$18-$37` HAL (`$18-$1B` fixed pointer registers), `$38-$FF` application
(cfg/rom.cfg, hal-api.md).
