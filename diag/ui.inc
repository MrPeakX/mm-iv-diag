; SPDX-License-Identifier: MIT
; diag/ui.inc -- shared definitions of the diagnostic application.

.ifndef UI_INC
UI_INC = 1

.include "hw.inc"

; 7-segment glyphs used for dynamic screens (font: hal/display.s).
G_A     = HW_SEG_A | HW_SEG_B | HW_SEG_C | HW_SEG_E | HW_SEG_F | HW_SEG_G
G_b     = HW_SEG_C | HW_SEG_D | HW_SEG_E | HW_SEG_F | HW_SEG_G
G_c     = HW_SEG_D | HW_SEG_E | HW_SEG_G
G_E     = HW_SEG_A | HW_SEG_D | HW_SEG_E | HW_SEG_F | HW_SEG_G
G_L     = HW_SEG_D | HW_SEG_E | HW_SEG_F
G_P     = HW_SEG_A | HW_SEG_B | HW_SEG_E | HW_SEG_F | HW_SEG_G
G_q     = HW_SEG_A | HW_SEG_B | HW_SEG_C | HW_SEG_F | HW_SEG_G
G_r     = HW_SEG_E | HW_SEG_G
G_t     = HW_SEG_D | HW_SEG_E | HW_SEG_F | HW_SEG_G
G_DASH  = HW_SEG_G
G_ALL   = $FF                   ; every segment incl. decimal point / colon
G_COLON = HW_SEG_DP             ; on digit 0: the colon

; Load a 16-bit address into a zero-page pointer.
.macro LDPTR ptr, addr
  lda #<(addr)
  sta ptr
  lda #>(addr)
  sta ptr+1
.endmacro

; Wait while serving the user interface (ui_wait); CL leaves the test.
.macro UI_WAIT ticks
  lda #<(ticks)
  ldx #>(ticks)
  jsr ui_wait
.endmacro

; diag/main.s: user interface core.
.global ui_wait, ui_poll, ui_show_num, ui_hex_screen
.global ui_heart_on, ui_heart_off, ui_show_square, menu
.globalzp ui_keys, ui_end, ui_tmp
; diag/romchk.s
.global rom_check
; Tests (diag/t_*.s), entered with JMP from the menu; leave with CL.
.global test_display, test_sound, test_keys, test_leds
.global test_sensors, test_ram, test_cart, test_info, test_egg

.endif
