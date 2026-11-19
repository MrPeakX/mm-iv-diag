; SPDX-License-Identifier: MIT
; runtime/font.s -- 7-segment hex digits (segment bits: include/hw.inc).

.include "hw.inc"
.include "timing.inc"
.include "runtime.inc"

.export rt_prefont_lo, rt_prefont_hi, rt_lcd_xor

SA = HW_SEG_A
SB = HW_SEG_B
SC = HW_SEG_C
SD = HW_SEG_D
SE = HW_SEG_E
SF = HW_SEG_F
SG = HW_SEG_G

HEX0 = SA|SB|SC|SD|SE|SF
HEX1 = SB|SC
HEX2 = SA|SB|SD|SE|SG
HEX3 = SA|SB|SC|SD|SG
HEX4 = SB|SC|SF|SG
HEX5 = SA|SC|SD|SF|SG
HEX6 = SA|SC|SD|SE|SF|SG
HEX7 = SA|SB|SC
HEX8 = SA|SB|SC|SD|SE|SF|SG
HEX9 = SA|SB|SC|SD|SF|SG
HEXA = SA|SB|SC|SE|SF|SG
HEXB = SC|SD|SE|SF|SG           ; b
HEXC = SA|SD|SE|SF
HEXD = SB|SC|SD|SE|SG           ; d
HEXE = SA|SD|SE|SF|SG
HEXF = SA|SE|SF|SG

.segment "RODATA"

rt_hexfont:
  .repeat 16, i
    .byte .ident(.sprintf("HEX%X", i))
  .endrepeat

; 256-entry tables: segments of the low / high nibble of the index. The
; pre-RAM failure loop has no RAM and keeps its values in X and Y, so it
; converts with a single indexed load.
rt_prefont_lo:
  .repeat 256, i
    .byte .ident(.sprintf("HEX%X", i & $0F))
  .endrepeat
rt_prefont_hi:
  .repeat 256, i
    .byte .ident(.sprintf("HEX%X", i >> 4))
  .endrepeat

; Per-digit XOR masks (include/timing.inc), index 0 = rightmost digit.
rt_lcd_xor:
  .byte LCD_XOR_DIGIT0, LCD_XOR_DIGIT1, LCD_XOR_DIGIT2, LCD_XOR_DIGIT3
