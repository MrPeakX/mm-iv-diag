; SPDX-License-Identifier: MIT
; diag/t_egg.s -- menu key 9 (Left / Black / 9): countdown and melody.
;
; A combined board LED and sound test (and a little show piece):
;   0. A smiley on the 8x8 field LEDs for 3 s; after 1 s it winks once
;      (right eye closed for a moment).
;   1. Countdown 9 ... 0 on the 8x8 field LEDs, one digit per second in a
;      bold font (2-pixel strokes), the digit also on the display, each
;      with a short ping.
;   2. Beethoven's "Ode to Joy" (Symphony No. 9, 4th movement, main theme,
;      transposed to C major, G4-G5) on the 1-bit speaker. The board shows
;      the pitch as a bar on files d/e, the display the frequency in Hz.
;   3. Back to the menu. CL leaves at any time (between notes).
;
; Timing constants: EGG_* in include/timing.inc.

.include "hal.inc"
.include "timing.inc"
.include "runtime.inc"
.include "ui.inc"

.segment "CODE"

test_egg:
  jsr disp_clear
  ; Smiley: open, wink, open again.
  ldx #EGG_SMILE
  jsr egg_show
  UI_WAIT EGG_WINK_AT_TICKS
  ldx #EGG_WINK
  jsr egg_show
  UI_WAIT EGG_WINK_TICKS
  ldx #EGG_SMILE
  jsr egg_show
  UI_WAIT EGG_SMILE_TICKS - EGG_WINK_AT_TICKS - EGG_WINK_TICKS

  lda #9
  sta ui_tmp                    ; digit
egg_count:
  lda ui_tmp
  asl a
  asl a
  asl a
  tax                           ; X = offset of the glyph
  jsr egg_show
  ldx ui_tmp
  lda rt_hexfont,x
  sta disp_buf
  SND_LDXY EGG_PING_FREQ
  lda #EGG_PING_DUR
  jsr snd_tone
  UI_WAIT EGG_COUNT_TICKS - EGG_PING_DUR * SND_DUR_TICKS
  dec ui_tmp
  bpl egg_count

  ; Melody.
  stz ui_tmp+1                  ; note index
egg_note:
  lda ui_tmp+1
  asl a
  tay
  ldx egg_song,y                ; X = pitch
  lda egg_song+1,y              ; A = tone duration
  beq egg_end
  sta ui_tmp+2
  stx ui_tmp+3
  ; Bar on files d and e: ranks 1 ... pitch + 4.
  ldx ui_tmp+3
  inx
  inx
  inx                           ; X = highest lit rank index
  ldy #0
egg_bar:
  lda #$18
  stx ui_tmp+4
  cpy ui_tmp+4
  bcc egg_lit
  beq egg_lit
  lda #0
egg_lit:
  sta brd_led,y
  iny
  cpy #8
  bne egg_bar
  ldy ui_tmp+3
  lda egg_hz_lo,y
  ldx egg_hz_hi,y
  jsr disp_dec
  lda ui_tmp+3
  asl a
  tay
  ldx egg_snd,y
  lda egg_snd+1,y
  tay
  lda ui_tmp+2
  jsr snd_tone
  jsr brd_led_alloff            ; articulation: board dark in the gap
  UI_WAIT EGG_GAP_DUR * SND_DUR_TICKS
  inc ui_tmp+1
  bra egg_note
egg_end:
  jsr disp_clear
  UI_WAIT EGG_END_TICKS
  jmp menu

; egg_show: copy one 8x8 glyph to the field LEDs.
; In: X = offset of the glyph in egg_font (top row, rank 8, first)
; Out: brd_led ranks 8 ... 1 = glyph rows
; Clobbers: A, X, Y
egg_show:
  ldy #7                        ; Y = rank index, top row first
@row:
  lda egg_font,x
  sta brd_led,y
  inx
  dey
  bpl @row
  rts

.segment "RODATA"

; Bold 8x8 digits 0-9, 2-pixel strokes. One string per row, top row
; (rank 8) first; character n = file a+n, '#' = LED on.
.macro EGG_ROW s
  .assert .strlen(s) = 8, error, "EGG_ROW: 8 characters"
  egg_row_v .set 0
  .repeat 8, i
    .if .strat(s, i) = '#'
      egg_row_v .set egg_row_v | (1 << i)
    .endif
  .endrepeat
  .byte egg_row_v
.endmacro

egg_font:
  ; 0
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##..##."
  EGG_ROW ".##..##."
  EGG_ROW ".##..##."
  EGG_ROW ".##..##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 1
  EGG_ROW "...##..."
  EGG_ROW "..###..."
  EGG_ROW ".####..."
  EGG_ROW "...##..."
  EGG_ROW "...##..."
  EGG_ROW "...##..."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 2
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".....##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##....."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 3
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".....##."
  EGG_ROW "..#####."
  EGG_ROW "..#####."
  EGG_ROW ".....##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 4
  EGG_ROW ".##..##."
  EGG_ROW ".##..##."
  EGG_ROW ".##..##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".....##."
  EGG_ROW ".....##."
  EGG_ROW ".....##."
  ; 5
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##....."
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".....##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 6
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##....."
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##..##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 7
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".....##."
  EGG_ROW "....##.."
  EGG_ROW "...##..."
  EGG_ROW "...##..."
  EGG_ROW "...##..."
  EGG_ROW "...##..."
  ; 8
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##..##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##..##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  ; 9
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".##..##."
  EGG_ROW ".######."
  EGG_ROW ".######."
  EGG_ROW ".....##."
  EGG_ROW ".######."
  EGG_ROW ".######."

; Smiley without outline (reads better on the sparse field LEDs), and the
; same face winking: right eye closed, only its bottom row stays lit.
EGG_SMILE = * - egg_font
  EGG_ROW "........"
  EGG_ROW ".##..##."
  EGG_ROW ".##..##."
  EGG_ROW "........"
  EGG_ROW "#......#"
  EGG_ROW ".#....#."
  EGG_ROW "..####.."
  EGG_ROW "........"
EGG_WINK = * - egg_font
  EGG_ROW "........"
  EGG_ROW ".##....."
  EGG_ROW ".##..##."
  EGG_ROW "........"
  EGG_ROW "#......#"
  EGG_ROW ".#....#."
  EGG_ROW "..####.."
  EGG_ROW "........"

; Pitches: G4 C5 D5 E5 F5 G5, equal temperament, A4 = 440 Hz.
P_G4 = 0
P_C5 = 1
P_D5 = 2
P_E5 = 3
P_F5 = 4
P_G5 = 5
.define EGG_HZ 392, 523, 587, 659, 698, 784
egg_hz_lo: .lobytes EGG_HZ
egg_hz_hi: .hibytes EGG_HZ
egg_snd:
  SND_BYTES 392
  SND_BYTES 523
  SND_BYTES 587
  SND_BYTES 659
  SND_BYTES 698
  SND_BYTES 784

; One note: pitch, length in eighth notes. The tone sounds for the length
; minus EGG_GAP_DUR, followed by the gap.
.macro N pitch, eighths
  .assert eighths * EGG_EIGHTH_DUR - EGG_GAP_DUR <= 255, error, "note too long"
  .byte pitch, eighths * EGG_EIGHTH_DUR - EGG_GAP_DUR
.endmacro

; Ode to Joy, 16 bars (Beethoven, op. 125, 4th movement, theme).
egg_song:
  N P_E5, 2
  N P_E5, 2
  N P_F5, 2
  N P_G5, 2
  N P_G5, 2
  N P_F5, 2
  N P_E5, 2
  N P_D5, 2
  N P_C5, 2
  N P_C5, 2
  N P_D5, 2
  N P_E5, 2
  N P_E5, 3
  N P_D5, 1
  N P_D5, 4

  N P_E5, 2
  N P_E5, 2
  N P_F5, 2
  N P_G5, 2
  N P_G5, 2
  N P_F5, 2
  N P_E5, 2
  N P_D5, 2
  N P_C5, 2
  N P_C5, 2
  N P_D5, 2
  N P_E5, 2
  N P_D5, 3
  N P_C5, 1
  N P_C5, 4

  N P_D5, 2
  N P_D5, 2
  N P_E5, 2
  N P_C5, 2
  N P_D5, 2
  N P_E5, 1
  N P_F5, 1
  N P_E5, 2
  N P_C5, 2
  N P_D5, 2
  N P_E5, 1
  N P_F5, 1
  N P_E5, 2
  N P_D5, 2
  N P_C5, 2
  N P_D5, 2
  N P_G4, 4

  N P_E5, 2
  N P_E5, 2
  N P_F5, 2
  N P_G5, 2
  N P_G5, 2
  N P_F5, 2
  N P_E5, 2
  N P_D5, 2
  N P_C5, 2
  N P_C5, 2
  N P_D5, 2
  N P_E5, 2
  N P_D5, 3
  N P_C5, 1
  N P_C5, 4
  .byte 0, 0                    ; end
