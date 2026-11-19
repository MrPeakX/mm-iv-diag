; SPDX-License-Identifier: MIT
; diag/main.s -- diagnostic application: power-on result, menu, idle
; display and the user interface core shared by all tests.
;
; Power-on (docs/codes.md): the runtime has passed its RAM tests and shows
; "dIAG". main checks the ROM (block CRCs, diag/romchk.s), shows the
; version, then "PASS" with a confirm beep or "E-03" with the error beep,
; and enters the menu.
;
; Menu: the idle display alternates "dIAG" and the version every
; IDLE_SCREEN_TICKS, with a wipe through all segments in between; after a
; ROM error at power-on it also shows "E-03" and the bad block mask. The
; keys 1-8 start a test, other keys click. In a test, CL returns to the
; menu and 0 pauses and resumes the test (ui_pause). In the key test, CL
; and 0 show their codes like any key; holding CL for 1 s leaves.
;
; Control flow: menu and tests never return. Starting a test or going
; back to the menu resets the stack (S = $FF) and jumps, so a test can
; leave from any call depth inside ui_wait.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"
.include "ident.inc"
.include "runtime.inc"
.include "ui.inc"

.import rpc_poll
.importzp rpc_hold
.export main, main_loop, app_banner
.exportzp diag_ready, boot_rom

DIAG_READY = $A5                ; diag_ready value once main runs
IDLE_MAX   = 4                  ; idle screens

.segment "ZEROPAGE"

; All application variables live in the zero page, so the RAM test
; (test 6) can test $0300-$1FFF destructively.
diag_ready: .res 1              ; DIAG_READY: application started (tests)
boot_rom:   .res 1              ; bad ROM blocks found at power-on (bit n = block n)
ui_mode:    .res 1              ; 0 = menu, 1 = test running
ui_keys:    .res 1              ; nonzero: ui_wait returns key presses to the test
ui_heart:   .res 1              ; nonzero: heartbeat (colon blinks)
ui_heart_t: .res 2              ; tick of the next heartbeat toggle
ui_end:     .res 2              ; ui_wait: end tick
ui_left:    .res 2              ; pause: ticks left of the interrupted ui_wait
ui_cl:      .res 1              ; nonzero: CL held in the key test
ui_cl_t:    .res 2              ; tick at which the held CL leaves the key test
ui_tmp:     .res 8              ; scratch for the tests
idle_scr:   .res 4 * IDLE_MAX   ; idle screens, 4 bytes each (disp_buf order)
idle_n:     .res 1              ; number of idle screens
idle_i:     .res 1              ; current idle screen

.segment "CODE"

; ---------------------------------------------------------------------------
; Power-on
; ---------------------------------------------------------------------------

main:
  lda #DIAG_READY
  sta diag_ready
  stz ui_mode
  jsr rom_check                 ; about 0.4 s, "dIAG" stays on
  sta boot_rom

  ; Idle screens: "dIAG", version, and after a ROM error "E-03", "b-mm".
  LDPTR hal_p0, str_banner
  LDPTR hal_p1, idle_scr
  jsr disp_str_to
  LDPTR hal_p0, IDENT_BASE + IDENT_VSTRING
  LDPTR hal_p1, idle_scr + 4
  jsr disp_str_to
  lda #2
  sta idle_n
  lda boot_rom
  beq @screens_done
  LDPTR hal_p0, str_e03
  LDPTR hal_p1, idle_scr + 8
  jsr disp_str_to
  lda boot_rom
  ldy #G_b
  jsr ui_hex_screen
  ldx #3
@copy:
  lda disp_buf,x
  sta idle_scr + 12,x
  dex
  bpl @copy
  lda #4
  sta idle_n
@screens_done:

  ; Version, then the result.
  ldx #3
@version:
  lda idle_scr + 4,x
  sta disp_buf,x
  dex
  bpl @version
  lda #<DIAG_VERSION_TICKS
  ldx #>DIAG_VERSION_TICKS
  jsr ui_wait
  lda boot_rom
  bne @rom_bad
  LDPTR hal_p0, str_pass
  jsr disp_str
  jsr snd_beep_ok
  bra @result
@rom_bad:
  LDPTR hal_p0, str_e03
  jsr disp_str
  jsr snd_beep_err
@result:
  lda #<DIAG_RESULT_TICKS
  ldx #>DIAG_RESULT_TICKS
  jsr ui_wait
  ; fall through

; ---------------------------------------------------------------------------
; Menu and idle display
; ---------------------------------------------------------------------------

; menu -- leave any test, reset the outputs, show the idle display.
menu:
  ldx #$FF
  txs
  jsr ui_reset
  stz ui_mode
  stz idle_i
@screen:
  jsr idle_wipe
  lda #<IDLE_SCREEN_TICKS
  ldx #>IDLE_SCREEN_TICKS
  jsr ui_wait
  inc idle_i
  lda idle_i
  cmp idle_n
  bcc @screen
  stz idle_i
  bra @screen

; idle_wipe -- wipe from the current display to idle screen idle_i: all
; segments on from left to right, hold, then the screen from left to
; right.
idle_wipe:
  ldx #HW_LCD_DIGITS - 1
@on:
  lda #G_ALL
  sta disp_buf,x
  jsr wipe_step
  dex
  bpl @on
  lda #<IDLE_ALLON_TICKS
  ldx #>IDLE_ALLON_TICKS
  jsr ui_wait
  lda idle_i
  asl a
  asl a
  ora #HW_LCD_DIGITS - 1
  tay                           ; Y = offset of the leftmost digit
  ldx #HW_LCD_DIGITS - 1
@new:
  lda idle_scr,y
  sta disp_buf,x
  jsr wipe_step
  dey
  dex
  bpl @new
  rts

; Preserves X and Y.
wipe_step:
  phx
  phy
  lda #<IDLE_WIPE_TICKS
  ldx #>IDLE_WIPE_TICKS
  jsr ui_wait
  ply
  plx
  rts

; start_test -- A = test number 1..8 (from the menu keys).
start_test:
  ldx #$FF
  txs
  pha
  jsr ui_reset
  jsr snd_click
  lda #1
  sta ui_mode
  ; Title "t-n".
  pla
  pha
  tax
  lda rt_hexfont,x
  sta disp_buf
  lda #G_DASH
  sta disp_buf+1
  lda #G_t
  sta disp_buf+2
  lda #<DIAG_TITLE_TICKS
  ldx #>DIAG_TITLE_TICKS
  jsr ui_wait
  pla
  dec a
  asl a
  tax
  jmp (test_table,x)

; ui_reset -- outputs to their idle state, events discarded.
; Clobbers: A, X, Y
ui_reset:
  stz ui_keys
  stz ui_cl
  jsr ui_heart_off
  lda #0
  jsr mled_set
  jsr brd_led_alloff
  jsr key_flush
  jsr brd_flush
  jmp disp_clear

; ---------------------------------------------------------------------------
; User interface core
; ---------------------------------------------------------------------------

; ui_wait -- wait A/X ticks while serving the user interface: test hook,
; heartbeat, keys. Keys (presses only):
;   menu:  1-8 start a test (does not return), others click
;   test:  CL returns to the menu (does not return); 0 pauses the test
;          (ui_pause); others click
;   test with ui_keys set (key test): every key is returned to the test,
;          also CL and 0; CL held for DIAG_CL_HOLD_TICKS returns to the
;          menu (does not return)
; Out: C = 0 time is up; C = 1 key press, A = key code (ui_keys only)
; Clobbers: A, X, Y
ui_wait:
  sta ui_end
  stx ui_end+1
  jsr tmr_read
  clc
  adc ui_end
  sta ui_end
  txa
  adc ui_end+1
  sta ui_end+1
main_loop:
  jsr rpc_poll                  ; test hook (diag/rpc.s)
  lda rpc_hold
  bne main_loop                 ; a test owns the HAL: only serve the hook
  lda ui_heart
  beq @cl_held
  jsr heart_tick
@cl_held:
  lda ui_cl
  beq @keys
  jsr cl_hold_tick              ; may leave to the menu
@keys:
  jsr key_get
  bcc @time
  bmi @time                     ; releases are not used
  ldx ui_mode
  bne @test_key
  tax
  lda menu_keys,x
  beq @click
  jmp start_test
@test_key:
  ldx ui_keys
  bne @key_test
  cmp #KEY_CL
  bne @not_cl
  jmp menu
@not_cl:
  cmp #KEY_RIGHT
  bne @click
  jmp ui_pause
@key_test:
  cmp #KEY_CL
  bne @to_test
  ; CL in the key test: shown like any key, leaves when held.
  jsr tmr_read
  clc
  adc #<DIAG_CL_HOLD_TICKS
  sta ui_cl_t
  txa
  adc #>DIAG_CL_HOLD_TICKS
  sta ui_cl_t+1
  lda #1
  sta ui_cl
  lda #KEY_CL
@to_test:
  sec
  rts
@click:
  jsr snd_click
@time:
  jsr tmr_read
  sec
  sbc ui_end
  txa
  sbc ui_end+1
  bmi main_loop
  clc
  rts

; ui_pause -- freeze the running test (key 0 in ui_wait): display, LEDs
; and module LEDs keep their state, so a faulty segment or LED can be
; watched while tapping or pressing on the unit. Confirm beep on entry.
; 0 resumes the interrupted ui_wait with the ticks it had left (click),
; CL returns to the menu, other keys click. Only the test hook keeps
; running. Continues in main_loop.
ui_pause:
  jsr tmr_read
  sta ui_left
  stx ui_left+1
  sec
  lda ui_end
  sbc ui_left
  sta ui_left
  lda ui_end+1
  sbc ui_left+1
  sta ui_left+1                 ; ticks left, may be <= 0
  jsr snd_beep_ok
@loop:
  jsr rpc_poll
  lda rpc_hold
  bne @loop
  jsr key_get
  bcc @loop
  bmi @loop                     ; releases are not used
  cmp #KEY_CL
  bne @not_cl
  jmp menu
@not_cl:
  cmp #KEY_RIGHT
  beq @resume
  jsr snd_click
  bra @loop
@resume:
  jsr snd_click
  jsr tmr_read
  clc
  adc ui_left
  sta ui_end
  txa
  adc ui_left+1
  sta ui_end+1
  jmp main_loop

; cl_hold_tick -- key test: CL still held when its time has come returns
; to the menu (does not return); a released CL disarms.
; Clobbers: A, X, Y
cl_hold_tick:
  lda #KEY_CL
  jsr key_down
  bcc @released
  jsr tmr_read
  sec
  sbc ui_cl_t
  txa
  sbc ui_cl_t+1
  bmi @done
  jmp menu
@released:
  stz ui_cl
@done:
  rts

; ui_poll -- one pass of ui_wait (no waiting).
; Out, Clobbers: as ui_wait
ui_poll:
  lda #0
  tax
  jmp ui_wait

; ui_heart_on -- start the heartbeat: the colon blinks every
; DIAG_HEART_TICKS while the test waits in ui_wait.
; ui_heart_off -- stop it, colon off.
; Clobbers: A, X
ui_heart_on:
  lda #1
  sta ui_heart
  jsr tmr_read
  sta ui_heart_t
  stx ui_heart_t+1
  rts
ui_heart_off:
  stz ui_heart
  lda disp_buf
  and #<~G_COLON
  sta disp_buf
  rts

; Toggle the colon when its time has come.
heart_tick:
  jsr tmr_read
  sec
  sbc ui_heart_t
  txa
  sbc ui_heart_t+1
  bmi @done
  lda ui_heart_t
  clc
  adc #<DIAG_HEART_TICKS
  sta ui_heart_t
  lda ui_heart_t+1
  adc #>DIAG_HEART_TICKS
  sta ui_heart_t+1
  lda disp_buf
  eor #G_COLON
  sta disp_buf
@done:
  rts

; ui_show_num -- decimal number with a letter in the leftmost digit.
; In:  A = low, X = high (0..9999), Y = glyph for digit 3 (used only if
;      the number leaves it blank)
; Clobbers: A, X, Y
ui_show_num:
  jsr disp_lock
  phy
  jsr disp_dec
  pla
  ldx disp_buf+3
  bne @done
  sta disp_buf+3
@done:
  jmp disp_unlock

; ui_hex_screen -- screen "L-hh": glyph, dash, byte in hex.
; In:  A = byte, Y = glyph for digit 3
; Clobbers: A, X, Y
ui_hex_screen:
  jsr disp_lock
  sty disp_buf+3
  ldx #0
  jsr disp_hex8
  lda #G_DASH
  sta disp_buf+2
  jmp disp_unlock

; ui_show_square -- square name in digits 1 and 0, e.g. "E4".
; In:  A = field (0..63)
; Clobbers: A, X
ui_show_square:
  pha
  and #7
  tax
  lda file_glyph,x
  sta disp_buf+1
  pla
  lsr a
  lsr a
  lsr a
  tax
  lda rt_hexfont+1,x            ; rank 1..8
  sta disp_buf
  rts

.segment "RODATA"

test_table:
  .addr test_display, test_sound, test_keys, test_leds
  .addr test_sensors, test_ram, test_cart, test_info
  .addr test_egg

; Test number per key code (include/hal.inc), 0 = no test.
menu_keys:
  .byte 0, 0, 0, 0, 0, 0, 0, 9  ; CL POS MEM INFO LEV ENT 0 9 (9: t_egg.s)
  .byte 5, 6, 7, 1, 8, 2, 3, 4  ; E5 F6 G7 A1 H8 B2 C3 D4

; Files a-h as 7-segment letters (A b C d E F G H).
file_glyph:
  .byte G_A, G_b, HW_SEG_A | HW_SEG_D | HW_SEG_E | HW_SEG_F
  .byte HW_SEG_B | HW_SEG_C | HW_SEG_D | HW_SEG_E | HW_SEG_G, G_E
  .byte HW_SEG_A | HW_SEG_E | HW_SEG_F | HW_SEG_G
  .byte HW_SEG_A | HW_SEG_C | HW_SEG_D | HW_SEG_E | HW_SEG_F
  .byte HW_SEG_B | HW_SEG_C | HW_SEG_E | HW_SEG_F | HW_SEG_G

str_banner: .byte "dIAG", 0
str_pass:   .byte "PASS", 0
str_e03:    .byte "E-03", 0

; Power-on banner "dIAG" as raw segments, index 0 = rightmost digit
; (disp_buf order). Used by the runtime before RAM is usable.
app_banner:
  .byte HW_SEG_A | HW_SEG_C | HW_SEG_D | HW_SEG_E | HW_SEG_F                ; G
  .byte HW_SEG_A | HW_SEG_B | HW_SEG_C | HW_SEG_E | HW_SEG_F | HW_SEG_G     ; A
  .byte HW_SEG_E | HW_SEG_F                                                 ; I
  .byte HW_SEG_B | HW_SEG_C | HW_SEG_D | HW_SEG_E | HW_SEG_G                ; d
