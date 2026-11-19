; SPDX-License-Identifier: MIT
; runtime/fatal.s -- fatal error display (docs/codes.md).
;
; Needs working zero page and stack (verified by the pre-RAM test), but
; neither the NMI handler nor any other RAM: it stops the HAL, then loops
; forever over up to three screens of about 1 s each, with LCD AC drive by
; busy waiting and an error tone at the start of each cycle:
;   "E-cc"   error code
;   "wwww"   rt_err_word in hex
;   "L-dd"   rt_err_data in hex, L = letter from fatal_letter (if any)

.include "hw.inc"
.include "timing.inc"
.include "runtime.inc"

SEG_E    = HW_SEG_A | HW_SEG_D | HW_SEG_E | HW_SEG_F | HW_SEG_G
SEG_DASH = HW_SEG_G

.segment "CODE"

; rt_fatal -- report a fatal error, never returns.
; In: A = error code (RT_E_*), rt_err_word, rt_err_data set as the code
;     requires.
rt_fatal:
  sei                           ; already set, the IRQ line is tied to VSS
  cld
  stz nmi_magic                 ; NMI handler: early exit only from now on
  ldx #$FF
  txs
  sta rt_err_code
  stz HW_LATCH + HW_Q_SPEAKER
  stz rt_f_phase

@cycle:
  ; Screen 1: "E-cc" with tone.
  lda rt_err_code
  jsr hex_pair
  lda #SEG_DASH
  sta rt_f_scr+2
  lda #SEG_E
  sta rt_f_scr+3
  lda #FATAL_BEEP_HALVES
  jsr show

  ; Screen 2: error word.
  lda rt_err_word+1
  jsr hex_pair
  lda rt_f_scr
  sta rt_f_scr+2
  lda rt_f_scr+1
  sta rt_f_scr+3
  lda rt_err_word
  jsr hex_pair
  lda #0
  jsr show

  ; Screen 3: letter and data byte, only for codes with a letter.
  lda rt_err_code
  and #$07
  tax
  lda fatal_letter,x
  beq @cycle
  sta rt_f_scr+3
  lda #SEG_DASH
  sta rt_f_scr+2
  lda rt_err_data
  jsr hex_pair
  lda #0
  jsr show
  bra @cycle

; Convert A to two hex digits in rt_f_scr+1 (high) and rt_f_scr (low).
hex_pair:
  pha
  and #$0F
  tax
  lda rt_hexfont,x
  sta rt_f_scr
  pla
  lsr a
  lsr a
  lsr a
  lsr a
  tax
  lda rt_hexfont,x
  sta rt_f_scr+1
  rts

; Show rt_f_scr for FATAL_SCREEN_HALVES half periods; the first A half
; periods with tone.
show:
  sta rt_f_beep
  lda #FATAL_SCREEN_HALVES
  sta rt_f_count
@half:
  lda rt_f_phase
  eor #$FF
  sta rt_f_phase
  lda rt_f_scr                  ; data first, then common (see disp_nmi)
  eor rt_f_phase
  eor #LCD_XOR_DIGIT0
  sta HW_LCD
  lda rt_f_scr+1
  eor rt_f_phase
  eor #LCD_XOR_DIGIT1
  sta HW_LCD
  lda rt_f_scr+2
  eor rt_f_phase
  eor #LCD_XOR_DIGIT2
  sta HW_LCD
  lda rt_f_scr+3
  eor rt_f_phase
  eor #LCD_XOR_DIGIT3
  sta HW_LCD
  lda rt_f_phase
  sta HW_LATCH + HW_Q_COMMON    ; D7 = new common

  ; Busy wait one half period, toggling Q6 every 2 inner loops while
  ; the tone is on (X bit 1 -> D7).
  ldx #FATAL_DELAY_OUTER
@outer:
  lda rt_f_beep
  beq @quiet
  txa
  asl a
  asl a
  asl a
  asl a
  asl a
  asl a
@quiet:
  sta HW_LATCH + HW_Q_SPEAKER
  ldy #0
@inner:
  dey
  bne @inner
  dex
  bne @outer

  lda rt_f_beep
  beq @next
  dec rt_f_beep
@next:
  dec rt_f_count
  bne @half
  stz HW_LATCH + HW_Q_SPEAKER
  rts

.segment "RODATA"

; Letter of screen 3 per error code (0 = no screen 3).
fatal_letter:
  .byte 0                                         ; -
  .byte HW_SEG_C|HW_SEG_D|HW_SEG_E|HW_SEG_F|HW_SEG_G ; RT_E_RAM: "b" (bits)
  .byte HW_SEG_E|HW_SEG_G                         ; RT_E_ADDR: "r" (read)
  .byte 0, 0, 0, 0, 0
