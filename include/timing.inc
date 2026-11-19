; SPDX-License-Identifier: MIT
; include/timing.inc -- all timing and tuning constants.
;
; Values that may need adjustment on a particular unit live here
; and nowhere else. Derived from HW_CLOCK_HZ / HW_NMI_HZ (include/hw.inc).

.ifndef TIMING_INC
TIMING_INC = 1

; --- LCD ------------------------------------------------------------------

; Per-digit XOR mask applied to the segment data before it is written.
; $00 for all digits on the MM IV display unit; set a digit to $FF if a
; display shows it inverted (docs/hardware.md, section 3). Index 0 =
; rightmost digit.
LCD_XOR_DIGIT0  = $00
LCD_XOR_DIGIT1  = $00
LCD_XOR_DIGIT2  = $00
LCD_XOR_DIGIT3  = $00

; NMIs per LCD common half period. The NMI handler toggles Q7 and
; rewrites the inverted data every LCD_AC_TICKS ticks:
; AC frequency = 600 / (2 * LCD_AC_TICKS) Hz, 5 -> 60 Hz.
; Q7 also selects the keypad bank, so each bank is read for
; LCD_AC_TICKS consecutive ticks.
LCD_AC_TICKS    = 5

; --- Fatal error and pre-RAM failure loops (no NMI time base) -------------

; Half period of the LCD AC drive in the busy-wait loops: outer count of
; 256 x 5-cycle inner loops, 32 -> about 41000 cycles = 8.3 ms (60 Hz AC).
FATAL_DELAY_OUTER = 32
; Half periods per screen of the fatal error display (120 -> ~1 s).
FATAL_SCREEN_HALVES = 120
; Half periods with error tone at the start of the first screen
; (36 -> ~0.3 s). The tone toggles Q6 every 2 inner loops: ~950 Hz.
FATAL_BEEP_HALVES = 36


; --- Time base ------------------------------------------------------------

; Ticks (NMIs, 600 Hz) for a duration in milliseconds, rounded down.
.define MS_TICKS(ms) ((ms) * HW_NMI_HZ / 1000)

; --- Keypad (hal/keys.s) --------------------------------------------------

; Each bank is sampled once per LCD common period (2 * LCD_AC_TICKS ticks,
; 60 Hz). A change of a bank is accepted after KEY_DEBOUNCE further
; samples with the same value: 2 -> 33..50 ms.
KEY_DEBOUNCE    = 2

; --- Sensor board (hal/board.s) -------------------------------------------

; One rank per tick, a full scan every 8 ticks (75 Hz). A change of a rank
; is accepted after BRD_DEBOUNCE further scans with the same value:
; 3 -> 40..53 ms. Real reed contacts bounce for a few ms.
BRD_DEBOUNCE    = 3
; Field LED blink: ticks per half period, 150 -> 2 Hz.
BRD_BLINK_TICKS = 150

; --- Sound (hal/sound.s) --------------------------------------------------

; Duration unit of snd_tone: ticks per unit, 6 -> 10 ms.
SND_DUR_TICKS   = 6
; Average NMI handler cycles (incl. entry and RTI) per 8192-cycle period
; while a tone plays, measured (docs/hal-api.md). The NMI stretches the
; tone loop by this much per period; the tone macros compensate.
SND_NMI_AVG     = 199
; Cycles per half period of the tone loop (hal/sound.s: snd_tone):
;   C = 5 * N + 4 * hi + 61, N = loop count, hi = (N - 1) >> 8
; f = HW_CLOCK_HZ / (2 * C) without NMIs.
; snd_tone parameters for frequency f in Hz (100..20000), computed with
; the NMI compensation:
;   SND_LDXY f   ldx #lo / ldy #hi
;   SND_BYTES f  .byte lo, hi (tone tables)
.macro SND_CALC f, lo, hi
  .local half, n
  half = (HW_CLOCK_HZ / (2 * (f))) * (HW_NMI_DIVIDER - SND_NMI_AVG) / HW_NMI_DIVIDER
  n = (half - 61 - 4 * (half / 1280)) / 5
  .assert n >= 1 && n <= 65536, error, "SND_CALC: frequency out of range"
  lo = (((n - 1) & $FF) + 1) & $FF
  hi = (n - 1) >> 8
.endmacro
.macro SND_LDXY f
  .local lo, hi
  SND_CALC f, lo, hi
  ldx #lo
  ldy #hi
.endmacro
.macro SND_BYTES f
  .local lo, hi
  SND_CALC f, lo, hi
  .byte lo, hi
.endmacro
; Standard beeps: frequency (Hz) and duration (10 ms units).
SND_OK_FREQ     = 2000          ; confirm beep
SND_OK_DUR      = 6
SND_ERR_FREQ    = 300           ; error beep: two long low tones
SND_ERR_DUR     = 25
SND_ERR_GAP     = MS_TICKS(100) ; ticks between the two error tones
SND_CLICK_FREQ  = 3000          ; key click
SND_CLICK_DUR   = 2

; --- Cartridge presence (hal/cart.s, docs/hardware.md section 7) ---------

CART_MIN_DISTINCT = 8           ; each page: at least this many distinct values
CART_MAX_ADDRHI   = 64          ; each page: at most this many bytes = address high byte

; --- Diagnostic application idle display (diag/main.s) -------------------

; While no test runs, the display alternates between "dIAG" and the
; version, with a wipe through all segments in between (sign of life).
IDLE_SCREEN_TICKS = MS_TICKS(5000) ; each screen
IDLE_WIPE_TICKS   = MS_TICKS(70)   ; per digit step of the wipe
IDLE_ALLON_TICKS  = MS_TICKS(250)  ; all segments on, between the wipes


; --- Diagnostic application (diag/) ---------------------------------------

DIAG_VERSION_TICKS = MS_TICKS(1000) ; power-on: version after "dIAG"
DIAG_RESULT_TICKS  = MS_TICKS(1000) ; power-on: "PASS" before the menu
DIAG_TITLE_TICKS   = MS_TICKS(700)  ; "t-n" when a test starts
DIAG_HEART_TICKS   = MS_TICKS(500)  ; heartbeat: colon blink half period
DIAG_CL_HOLD_TICKS = MS_TICKS(1000) ; key test: hold CL this long to leave

; Test 1, display.
T1_ALL_TICKS    = MS_TICKS(5000)    ; all segments on (time to note dead segments)
T1_DIGIT_TICKS  = MS_TICKS(500)     ; one digit fully on
T1_SEG_TICKS    = MS_TICKS(400)     ; one segment on all digits
T1_OFF_TICKS    = MS_TICKS(500)     ; all off at the end of a round
; Test 2, sound: each note of the scale (10 ms units), pause after it.
T2_NOTE_DUR     = 30
T2_GAP_TICKS    = MS_TICKS(60)
T2_PAUSE_TICKS  = MS_TICKS(1000)
; Test 4, LEDs.
T4_FIELD_TICKS  = MS_TICKS(80)      ; running light, per field
T4_MLED_TICKS   = MS_TICKS(300)     ; per module LED
T4_ALL_TICKS    = MS_TICKS(5000)    ; everything on (time to note dead LEDs)
; Test 6, RAM / ROM loop, and test 7/8: screen time of cycling screens.
T6_SCREEN_TICKS = MS_TICKS(1000)
T7_SCREEN_TICKS = MS_TICKS(1200)
T8_SCREEN_TICKS = MS_TICKS(1500)
; Menu key 9 (diag/t_egg.s): smiley (winks once), countdown 9 ... 0 on the
; board, then "Ode to Joy". Durations in snd_tone units (SND_DUR_TICKS, 10 ms).
EGG_SMILE_TICKS = MS_TICKS(3000)    ; smiley on the board, wink included
EGG_WINK_AT_TICKS = MS_TICKS(1000)  ; smiley open before the wink
EGG_WINK_TICKS  = MS_TICKS(400)     ; one eye closed
EGG_COUNT_TICKS = MS_TICKS(1000)    ; one countdown step, ping included
EGG_PING_FREQ   = 1760              ; ping (A6)
EGG_PING_DUR    = 8                 ; 80 ms
EGG_EIGHTH_DUR  = 20                ; eighth note 200 ms (quarter = 150 bpm)
EGG_GAP_DUR     = 3                 ; silence at the end of every note
EGG_END_TICKS   = MS_TICKS(1500)    ; after the last note, then the menu

.endif
