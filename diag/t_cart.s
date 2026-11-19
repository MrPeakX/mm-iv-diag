; SPDX-License-Identifier: MIT
; diag/t_cart.s -- test 7: cartridge (opening library) in the slot.
; Repeats until CL: "----" while checking (about 1 s), then
;   "nonE"   no cartridge (plausibility rule, docs/hardware.md section 7)
;   " 440"   HG 440 (MM IV)       followed by the CRC-32 of $4000-$7FFF
;   " 550"   HG 550 (MM V)        as two screens: high word, low word
;   "CArt"   unknown cartridge    (e.g. "81FF", "CdFd")

.include "hal.inc"
.include "timing.inc"
.include "ui.inc"

.segment "CODE"

test_cart:
  lda #G_DASH
  jsr disp_fill
  jsr ui_poll
  jsr cart_check
  sta ui_tmp
  ldx #3
@save:
  lda crc_val,x
  sta ui_tmp+1,x
  dex
  bpl @save
  lda ui_tmp
  asl a
  tax
  lda id_str,x
  sta hal_p0
  lda id_str+1,x
  sta hal_p0+1
  jsr disp_str
  UI_WAIT T7_SCREEN_TICKS
  lda ui_tmp
  beq test_cart                 ; CART_NONE: no checksum
  lda ui_tmp+3
  ldx ui_tmp+4
  jsr disp_hex16
  UI_WAIT T7_SCREEN_TICKS
  lda ui_tmp+1
  ldx ui_tmp+2
  jsr disp_hex16
  UI_WAIT T7_SCREEN_TICKS
  bra test_cart

.segment "RODATA"

id_str: .addr str_none, str_unknown, str_440, str_550   ; CART_* order
str_none:    .byte "nonE", 0
str_unknown: .byte "CArt", 0
str_440:     .byte "440", 0
str_550:     .byte "550", 0
