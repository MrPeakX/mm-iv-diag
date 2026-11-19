; SPDX-License-Identifier: MIT
; diag/t_leds.s -- test 4: LEDs. Repeats until CL:
;   running light over the 64 fields a1, b1 ... h8 (square on the
;   display), the 6 module LEDs Q0-Q5 ("L-0q"), then everything on
;   ("ALL").

.include "hal.inc"
.include "timing.inc"
.include "ui.inc"

.segment "CODE"

test_leds:
  jsr disp_clear
  stz ui_tmp                    ; field
@field:
  jsr brd_led_alloff
  lda ui_tmp
  jsr brd_led_set
  lda ui_tmp
  jsr ui_show_square
  UI_WAIT T4_FIELD_TICKS
  inc ui_tmp
  lda ui_tmp
  cmp #64
  bne @field
  jsr brd_led_alloff

  stz ui_tmp                    ; module LED number
@mled:
  ldx ui_tmp
  lda q_bit,x
  jsr mled_set
  lda ui_tmp
  ldy #G_L
  jsr ui_hex_screen
  UI_WAIT T4_MLED_TICKS
  inc ui_tmp
  lda ui_tmp
  cmp #HW_Q_LED5 + 1
  bne @mled

  jsr brd_led_all
  lda #$3F
  jsr mled_set
  LDPTR hal_p0, str_all
  jsr disp_str
  UI_WAIT T4_ALL_TICKS
  lda #0
  jsr mled_set
  bra test_leds

.segment "RODATA"

q_bit:   .byte $01, $02, $04, $08, $10, $20
str_all: .byte "ALL", 0
