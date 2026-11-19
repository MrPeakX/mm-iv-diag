; SPDX-License-Identifier: MIT
; diag/t_display.s -- test 1: display. Repeats until CL:
;   all segments on, each digit position fully on (left to right), each
;   segment line on all digits (a, b, c, d, e, f, g, decimal points and
;   colon), all off.

.include "hal.inc"
.include "timing.inc"
.include "ui.inc"

.segment "CODE"

test_display:
  lda #G_ALL
  jsr disp_fill
  UI_WAIT T1_ALL_TICKS
  ; Each digit, left to right.
  lda #HW_LCD_DIGITS - 1
  sta ui_tmp
@digit:
  jsr disp_clear
  ldx ui_tmp
  lda #G_ALL
  sta disp_buf,x
  UI_WAIT T1_DIGIT_TICKS
  dec ui_tmp
  bpl @digit
  ; Each segment line (bit 0 = a ... bit 7 = DP / colon) on all digits.
  lda #1
  sta ui_tmp
@segment:
  lda ui_tmp
  jsr disp_fill
  UI_WAIT T1_SEG_TICKS
  asl ui_tmp
  bne @segment
  jsr disp_clear
  UI_WAIT T1_OFF_TICKS
  bra test_display
