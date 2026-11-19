; SPDX-License-Identifier: MIT
; diag/t_sound.s -- test 2: sound. Plays the C major scale C5-C6 (one
; note per T2_NOTE_DUR, frequency in Hz on the display), pauses, repeats
; until CL.

.include "hal.inc"
.include "timing.inc"
.include "ui.inc"

NOTES = 8

.segment "CODE"

test_sound:
  stz ui_tmp                    ; note index
@note:
  ldy ui_tmp
  lda note_hz_lo,y
  ldx note_hz_hi,y
  jsr disp_dec
  lda ui_tmp
  asl a
  tay
  ldx note_snd,y
  lda note_snd+1,y
  tay
  lda #T2_NOTE_DUR
  jsr snd_tone
  UI_WAIT T2_GAP_TICKS
  inc ui_tmp
  lda ui_tmp
  cmp #NOTES
  bne @note
  UI_WAIT T2_PAUSE_TICKS
  bra test_sound

.segment "RODATA"

; Equal temperament, A4 = 440 Hz, rounded to 1 Hz.
.define NOTE_HZ 523, 587, 659, 698, 784, 880, 988, 1047
note_hz_lo: .lobytes NOTE_HZ
note_hz_hi: .hibytes NOTE_HZ
note_snd:
  SND_BYTES 523
  SND_BYTES 587
  SND_BYTES 659
  SND_BYTES 698
  SND_BYTES 784
  SND_BYTES 880
  SND_BYTES 988
  SND_BYTES 1047
