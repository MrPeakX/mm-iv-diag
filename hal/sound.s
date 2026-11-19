; SPDX-License-Identifier: MIT
; hal/sound.s -- 1-bit speaker on latch Q6 (docs/hardware.md, section 5).
;
; There is no tone generator: snd_tone toggles Q6 in a timed loop. The
; frequency is set by a loop count computed at assembly time with the
; SND_LDXY macros (include/timing.inc), which include the loop
; overhead and compensate the average NMI load (SND_NMI_AVG). The NMI
; still adds jitter: a half period hit by an NMI is longer by the handler
; time (about 0.1 ms), heard as a slight roughness, not as a pitch change.
; The duration is measured with the 600 Hz tick counter, so it is exact
; to one tick regardless of the frequency.
;
; snd_tone blocks the foreground for the duration of the tone; the NMI
; handler (display, keys, board) keeps running.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"
.include "runtime.inc"

.segment "HALZP": zeropage

snd_hp:   .res 2                ; loop count, SND_LDXY
snd_left: .res 2                ; ticks left
snd_last: .res 1                ; rt_ticks low byte at the last check
snd_out:  .res 1                ; next value for Q6 (D7)
snd_tmp:  .res 1                ; ticks elapsed in this pass

.segment "CODE"

; snd_tone -- play a square wave.
; In:  X, Y = loop count for the frequency (SND_LDXY f), A = duration in units of
;      SND_DUR_TICKS ticks (10 ms), 0 = no tone
; Out: speaker off (Q6 = 0)
; Clobbers: A, X, Y
snd_tone:
  stx snd_hp
  sty snd_hp+1
  ; snd_left = A * SND_DUR_TICKS
  stz snd_left
  stz snd_left+1
  tay
  beq @end
  ldx #SND_DUR_TICKS
@mul:
  tya
  clc
  adc snd_left
  sta snd_left
  bcc @mul_next
  inc snd_left+1
@mul_next:
  dex
  bne @mul
  lda rt_ticks
  sta snd_last
  lda #HW_LATCH_ON
  sta snd_out

  ; One half period per pass, C = 5 * N + 4 * hi + 61 cycles
  ; (include/timing.inc: SND_CALC). Cycle counts in the comments.
@half:
  lda snd_out                   ; 3
  sta HW_LATCH + HW_Q_SPEAKER   ; 4
  eor #HW_LATCH_ON              ; 2
  sta snd_out                   ; 3
  ldx snd_hp                    ; 3
  ldy snd_hp+1                  ; 3
  iny                           ; 2
@delay:
  dex                           ; 2
  bne @delay                    ; 3 / 2
  dey                           ; 2
  bne @delay                    ; 3 / 2
  ; Ticks elapsed since the last pass (also when one NMI or more came).
  lda rt_ticks                  ; 3
  tax                           ; 2
  sec                           ; 2
  sbc snd_last                  ; 3
  stx snd_last                  ; 3
  sta snd_tmp                   ; 3
  lda snd_left                  ; 3
  sec                           ; 2
  sbc snd_tmp                   ; 3
  sta snd_left                  ; 3
  lda snd_left+1                ; 3
  sbc #0                        ; 2
  sta snd_left+1                ; 3
  bcs @half                     ; 3
@end:
  stz HW_LATCH + HW_Q_SPEAKER
  rts

; snd_beep_ok -- short confirm beep (SND_OK_FREQ, SND_OK_DUR).
; Clobbers: A, X, Y
snd_beep_ok:
  SND_LDXY SND_OK_FREQ
  lda #SND_OK_DUR
  bra snd_tone

; snd_click -- very short key click (SND_CLICK_FREQ, SND_CLICK_DUR).
; Clobbers: A, X, Y
snd_click:
  SND_LDXY SND_CLICK_FREQ
  lda #SND_CLICK_DUR
  bra snd_tone

; snd_beep_err -- error beep: two low tones (SND_ERR_*).
; Clobbers: A, X, Y
snd_beep_err:
  jsr @tone
  lda #<SND_ERR_GAP
  ldx #>SND_ERR_GAP
  jsr tmr_wait
@tone:
  SND_LDXY SND_ERR_FREQ
  lda #SND_ERR_DUR
  bra snd_tone
