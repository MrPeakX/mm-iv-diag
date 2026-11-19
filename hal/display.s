; SPDX-License-Identifier: MIT
; hal/display.s -- LCD display unit (docs/hardware.md, section 3).
;
; disp_buf holds the logical segment patterns, index 0 = rightmost digit.
; The NMI handler owns the hardware: every LCD_AC_TICKS ticks hal_nmi
; calls disp_nmi, which rewrites all four digits as buf XOR phase XOR
; LCD_XOR_DIGITn for the next phase and then toggles the common (latch
; Q7), so the visible image never changes and the LCD sees no DC
; (docs/hardware.md, section 3).
; Foreground routines only write disp_buf; a change becomes visible with
; the next common toggle (at most LCD_AC_TICKS ticks, 8.3 ms).
;
; Multi-step updates (disp_dec, disp_str, disp_hex16, disp_set4, disp_fill
; and the diag/ screens built on them) are atomic with respect to the NMI:
; while disp_hold is non-zero, hal_nmi postpones the common toggle by one
; tick, so the LCD never receives a half-built buffer (e.g. the leading
; zeros disp_dec writes before it blanks them). disp_lock/disp_unlock
; nest. Direct writes to disp_buf are still allowed for single bytes.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"
.include "runtime.inc"

.exportzp disp_count, disp_hold

.segment "HALZP": zeropage

disp_buf:   .res HW_LCD_DIGITS  ; logical segments, index 0 = rightmost
disp_phase: .res 1              ; current common: $00 (Q7 = 0) or $FF (Q7 = 1)
disp_count: .res 1              ; ticks until the next common toggle (hal_nmi)
disp_tmp:   .res 2              ; foreground scratch (disp_dec, disp_str)
disp_hold:  .res 1              ; lock count: non-zero postpones the toggle

.segment "CODE"

; disp_init -- set up the display state; the NMI takes over from here.
; In:  disp_buf already filled by the caller (or garbage, shown as is).
; Out: -
; Clobbers: A
disp_init:
  stz disp_phase
  stz HW_LATCH + HW_Q_COMMON
  lda #1
  sta disp_count                ; refresh on the first tick
  rts

; disp_lock -- start an atomic multi-step update of disp_buf. Nests.
; The NMI postpones the display refresh (by one tick at a time) until the
; matching disp_unlock. Keep the locked section short (a few hundred
; cycles); never wait for a key or a timer while locked.
; Clobbers: -
disp_lock:
  inc disp_hold
  rts

; disp_unlock -- end the update; the new content shows at the next toggle.
; Clobbers: -
disp_unlock:
  dec disp_hold
  rts

; disp_nmi -- NMI part: toggle the common and rewrite all digits.
; Called by hal_nmi every LCD_AC_TICKS ticks.
; Clobbers: A
; The data for the new phase is shifted in first, the common follows
; (docs/hardware.md, section 3).
disp_nmi:
  lda disp_phase
  eor #$FF
  sta disp_phase
  lda disp_buf
  eor disp_phase
  eor #LCD_XOR_DIGIT0
  sta HW_LCD                    ; first byte ends up in digit 0
  lda disp_buf+1
  eor disp_phase
  eor #LCD_XOR_DIGIT1
  sta HW_LCD
  lda disp_buf+2
  eor disp_phase
  eor #LCD_XOR_DIGIT2
  sta HW_LCD
  lda disp_buf+3
  eor disp_phase
  eor #LCD_XOR_DIGIT3
  sta HW_LCD
  lda disp_phase
  sta HW_LATCH + HW_Q_COMMON    ; D7 = new common
  rts

; disp_clear -- all segments off.
; Clobbers: A
disp_clear:
  lda #0
  ; fall through

; disp_fill -- the same segment pattern on all four digits.
; In:  A = segments ($FF = everything incl. decimal points and colon)
; Clobbers: -
disp_fill:
  inc disp_hold
  sta disp_buf
  sta disp_buf+1
  sta disp_buf+2
  sta disp_buf+3
  dec disp_hold
  rts

; disp_raw -- raw segments on one digit.
; In:  A = segments (include/hw.inc HW_SEG_*), X = digit (0 = rightmost)
; Clobbers: -
disp_raw:
  sta disp_buf,x
  rts

; disp_set4 -- raw segments on all digits from a 4-byte table.
; In:  hal_p0 = table, byte 0 = rightmost digit
; Clobbers: A, Y
disp_set4:
  inc disp_hold
  ldy #HW_LCD_DIGITS - 1
@copy:
  lda (hal_p0),y
  sta disp_buf,y
  dey
  bpl @copy
  dec disp_hold
  rts

; disp_hex8 -- byte as two hex digits.
; In:  A = value, X = digit of the low nibble (0..2); the high nibble
;      goes to digit X+1
; Clobbers: A, Y
disp_hex8:
  pha
  and #$0F
  tay
  lda rt_hexfont,y
  sta disp_buf,x
  pla
  lsr a
  lsr a
  lsr a
  lsr a
  tay
  lda rt_hexfont,y
  sta disp_buf+1,x
  rts

; disp_hex16 -- 16-bit value as four hex digits.
; In:  A = low byte, X = high byte
; Clobbers: A, X, Y
disp_hex16:
  inc disp_hold
  phx
  ldx #0
  jsr disp_hex8
  pla
  ldx #2
  jsr disp_hex8
  dec disp_hold
  rts

; disp_dec -- 16-bit value as up to four decimal digits, right aligned,
; leading zeros blank. Values above 9999 show "----".
; In:  A = low byte, X = high byte
; Clobbers: A, X, Y, disp_tmp
disp_dec:
  inc disp_hold
  jsr disp_dec_i
  dec disp_hold
  rts

disp_dec_i:
  sta disp_tmp
  stx disp_tmp+1
  cpx #>10000
  bcc @range
  bne @over
  cmp #<10000
  bcc @range
@over:
  lda #HW_SEG_G
  bra disp_fill
@range:
  ; Digits 3..1 by repeated subtraction of 1000, 100, 10.
  ldx #HW_LCD_DIGITS - 1
@digit:
  ldy #0
@sub:
  lda disp_tmp
  sec
  sbc dec_lo-1,x
  pha
  lda disp_tmp+1
  sbc dec_hi-1,x
  bcc @done
  sta disp_tmp+1
  pla
  sta disp_tmp
  iny
  bra @sub
@done:
  pla
  lda rt_hexfont,y
  sta disp_buf,x
  dex
  bne @digit
  ldy disp_tmp
  lda rt_hexfont,y
  sta disp_buf
  ; Blank leading zeros (digits 3..1).
  ldx #HW_LCD_DIGITS - 1
@blank:
  lda disp_buf,x
  cmp rt_hexfont                ; "0"
  bne @end
  stz disp_buf,x
  dex
  bne @blank
@end:
  rts

; disp_str -- ASCII string in 7-segment form, right aligned.
; disp_str_to -- the same into any 4-byte buffer (index 0 = rightmost).
; In:  hal_p0 = NUL-terminated string; disp_str_to: hal_p1 = buffer
;      Characters $20-$7F (font: disp_font), others show blank.
;      '.' sets the decimal point of the character before it (digits
;      3..1 only; digit 0 has none). ':' lights the colon and takes no
;      digit. Only the last four characters are shown; unused digits on
;      the left are blank.
; Out: -
; Clobbers: A, X, Y, disp_tmp; disp_str also hal_p1
disp_str:
  lda #<disp_buf
  sta hal_p1
  stz hal_p1+1
disp_str_to:
  inc disp_hold
  jsr disp_str_i
  dec disp_hold
  rts

disp_str_i:
  ; Clear the buffer; find the end of the string.
  ldy #HW_LCD_DIGITS - 1
  lda #0
@clear:
  sta (hal_p1),y
  dey
  bpl @clear
  stz disp_tmp                  ; next digit to fill
  stz disp_tmp+1                ; pending decimal point
  ldy #$FF
@len:
  iny
  lda (hal_p0),y
  bne @len
@char:
  dey
  cpy #$FF
  beq @end
  lda (hal_p0),y
  cmp #'.'
  beq @dot
  cmp #':'
  beq @colon
  sec
  sbc #$20
  bcc @blank
  cmp #$60
  bcs @blank
  tax
  lda disp_font,x
  bra @put
@blank:
  lda #0
@put:
  ora disp_tmp+1
  stz disp_tmp+1
  phy
  ldy disp_tmp
  sta (hal_p1),y
  ply
  inc disp_tmp
  lda disp_tmp
  cmp #HW_LCD_DIGITS
  bne @char
  rts
@dot:
  lda disp_tmp                  ; digit 0 has no decimal point
  beq @char
  lda #HW_SEG_DP
  sta disp_tmp+1
  bra @char
@colon:
  phy
  ldy #0
  lda (hal_p1),y
  ora #HW_SEG_DP                ; colon = digit 0 bit 7
  sta (hal_p1),y
  ply
  bra @char
@end:
  ; A string starting with '.': blank digit with decimal point.
  lda disp_tmp+1
  beq @done
  ldy disp_tmp
  sta (hal_p1),y
@done:
  rts

.segment "RODATA"

dec_lo: .byte <10, <100, <1000  ; indexed by digit - 1
dec_hi: .byte >10, >100, >1000

SA = HW_SEG_A
SB = HW_SEG_B
SC = HW_SEG_C
SD = HW_SEG_D
SE = HW_SEG_E
SF = HW_SEG_F
SG = HW_SEG_G

; 7-segment font for ASCII $20-$7F. Letters without a usable 7-segment
; form share a glyph (K/X look like H, M/N/W like n, V like u). Upper and
; lower case differ where both forms exist (b/B, c/C, h/H, o/O, u/U).
disp_font:
  ; $20  space ! " # $ % & '
  .byte 0, SB|SC, SB|SF, 0, SA|SC|SD|SF|SG, 0, 0, SB
  ; $28  ( ) * + , - . /
  .byte SA|SD|SE|SF, SA|SB|SC|SD, SA|SB|SF|SG, 0, 0, SG, 0, SB|SE|SG
  ; $30  0-7
  .byte SA|SB|SC|SD|SE|SF, SB|SC, SA|SB|SD|SE|SG, SA|SB|SC|SD|SG
  .byte SB|SC|SF|SG, SA|SC|SD|SF|SG, SA|SC|SD|SE|SF|SG, SA|SB|SC
  ; $38  8 9 : ; < = > ?
  .byte SA|SB|SC|SD|SE|SF|SG, SA|SB|SC|SD|SF|SG, 0, 0, SD|SE|SG, SD|SG, SC|SD|SG, SA|SB|SE|SG
  ; $40  @ A B C D E F G
  .byte SA|SB|SD|SE|SF|SG, SA|SB|SC|SE|SF|SG, SC|SD|SE|SF|SG, SA|SD|SE|SF
  .byte SB|SC|SD|SE|SG, SA|SD|SE|SF|SG, SA|SE|SF|SG, SA|SC|SD|SE|SF
  ; $48  H I J K L M N O
  .byte SB|SC|SE|SF|SG, SE|SF, SB|SC|SD|SE, SB|SC|SE|SF|SG
  .byte SD|SE|SF, SC|SE|SG, SC|SE|SG, SA|SB|SC|SD|SE|SF
  ; $50  P Q R S T U V W
  .byte SA|SB|SE|SF|SG, SA|SB|SC|SF|SG, SE|SG, SA|SC|SD|SF|SG
  .byte SD|SE|SF|SG, SB|SC|SD|SE|SF, SC|SD|SE, SC|SD|SE
  ; $58  X Y Z [ \ ] ^ _
  .byte SB|SC|SE|SF|SG, SB|SC|SD|SF|SG, SA|SB|SD|SE|SG, SA|SD|SE|SF
  .byte SC|SF|SG, SA|SB|SC|SD, SA|SB|SF, SD
  ; $60  ` a b c d e f g
  .byte SF, SA|SB|SC|SD|SE|SG, SC|SD|SE|SF|SG, SD|SE|SG
  .byte SB|SC|SD|SE|SG, SA|SB|SD|SE|SF|SG, SA|SE|SF|SG, SA|SB|SC|SD|SF|SG
  ; $68  h i j k l m n o
  .byte SC|SE|SF|SG, SE, SC|SD, SB|SC|SE|SF|SG
  .byte SE|SF, SC|SE|SG, SC|SE|SG, SC|SD|SE|SG
  ; $70  p q r s t u v w
  .byte SA|SB|SE|SF|SG, SA|SB|SC|SF|SG, SE|SG, SA|SC|SD|SF|SG
  .byte SD|SE|SF|SG, SC|SD|SE, SC|SD|SE, SC|SD|SE
  ; $78  x y z { | } ~ DEL
  .byte SB|SC|SE|SF|SG, SB|SC|SD|SF|SG, SA|SB|SD|SE|SG, SA|SD|SE|SF
  .byte SE|SF, SA|SB|SC|SD, SA, 0
