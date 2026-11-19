; SPDX-License-Identifier: MIT
; diag/t_sensors.s -- test 5: sensors. Every field LED shows its sensor:
; a piece lights the field. The display shows the number of pieces
; ("P nn") until the first change, then the last change: "P-E4" piece
; placed on e4, "L-E4" piece lifted from e4, with a click. The colon
; blinks (heartbeat).

.include "hal.inc"
.include "timing.inc"
.include "ui.inc"

.segment "CODE"

test_sensors:
  jsr ui_heart_on
  ; Number of pieces.
  stz ui_tmp
  ldx #7
@rank:
  lda brd_state,x
@bit:
  asl a
  bcc @empty
  inc ui_tmp
@empty:
  cmp #0
  bne @bit
  dex
  bpl @rank
  lda ui_tmp
  ldx #0
  ldy #G_P
  jsr ui_show_num

@loop:
  ; LEDs follow the sensors.
  ldx #7
@mirror:
  lda brd_state,x
  sta brd_led,x
  dex
  bpl @mirror
  jsr brd_get
  bcc @idle
  pha
  ldy #G_L
  and #BRD_PLACED
  beq @letter
  ldy #G_P
@letter:
  sty disp_buf+3
  lda #G_DASH
  sta disp_buf+2
  pla
  and #$3F
  jsr ui_show_square
  jsr snd_click
@idle:
  UI_WAIT 1
  bra @loop
