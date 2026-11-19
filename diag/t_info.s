; SPDX-License-Identifier: MIT
; diag/t_info.s -- test 8: info from the ident block. Cycles until CL:
;   version (" 1.0.0"), build date UTC: year ("2026"), month.day
;   ("11.01"), hours:minutes ("02:16"), then "Crc" and the ROM CRC-32
;   from the ident block as two screens (high word, low word).

.include "hal.inc"
.include "timing.inc"
.include "ident.inc"
.include "ui.inc"

BUILD = IDENT_BASE + IDENT_BUILD    ; "YYYY-MM-DD HH:MM:SS"
CRC   = IDENT_BASE + IDENT_CRC

.segment "CODE"

test_info:
  LDPTR hal_p0, IDENT_BASE + IDENT_VSTRING
  jsr show
  ldx #0                        ; year
  jsr build_str
  jsr show_tmp
  ldx #fmt_date - fmt
  jsr build_str
  jsr show_tmp
  ldx #fmt_time - fmt
  jsr build_str
  jsr show_tmp
  LDPTR hal_p0, str_crc
  jsr show
  lda CRC+2
  ldx CRC+3
  jsr disp_hex16
  UI_WAIT T8_SCREEN_TICKS
  lda CRC
  ldx CRC+1
  jsr disp_hex16
  UI_WAIT T8_SCREEN_TICKS
  bra test_info

show_tmp:
  LDPTR hal_p0, ui_tmp
show:
  jsr disp_str
  UI_WAIT T8_SCREEN_TICKS
  rts

; build_str -- string in ui_tmp from the format at fmt + X: offsets into
; the build time string, or a literal character with bit 7 set; $00 ends.
build_str:
  ldy #0
@char:
  lda fmt,x
  beq @end
  bmi @literal
  phx
  tax
  lda BUILD - 1,x               ; offsets are stored + 1 (0 ends)
  plx
  bra @put
@literal:
  and #$7F
@put:
  sta ui_tmp,y
  iny
  inx
  bra @char
@end:
  sta ui_tmp,y
  rts

.segment "RODATA"

; Offsets + 1 into "YYYY-MM-DD HH:MM:SS"; $80 | c = literal c.
fmt:      .byte 1, 2, 3, 4, 0                        ; YYYY
fmt_date: .byte 6, 7, $80 | '.', 9, 10, 0            ; MM.DD
fmt_time: .byte 12, 13, $80 | ':', 15, 16, 0         ; HH:MM
str_crc:  .byte "Crc", 0
