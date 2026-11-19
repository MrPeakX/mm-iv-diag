; SPDX-License-Identifier: MIT
; hal/keys.s -- keypad scan, debounce and key events.
;
; Hardware (docs/hardware.md, section 4): $2C00+n reads
; key n of the bank selected by latch Q7 in bit 7, active low. Q7 is also
; the LCD common, which the NMI toggles every LCD_AC_TICKS ticks. hal_nmi
; calls key_nmi just before each toggle, so the bank being read has been
; selected for a whole LCD half period (no settling issue) and each bank
; is sampled once per common period (60 Hz).
;
; Debounce: a bank's new 8-bit sample is accepted when KEY_DEBOUNCE
; further samples are equal to it. Every accepted change of a key puts an
; event into a queue: key code (include/hal.inc KEY_*), bit 7 set for a
; release. The queue holds KEY_QSIZE - 1 events; more are dropped.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"

.importzp nmi_t0, nmi_t1, nmi_t2
.import hal_bit

KEY_QSIZE = 8                   ; power of two

.segment "HALBSS"

key_prev:  .res 2               ; last raw sample per bank, 1 = pressed
key_cnt:   .res 2               ; equal samples since the last change
key_state: .res 2               ; debounced state per bank, 1 = pressed
key_q:     .res KEY_QSIZE       ; event queue
key_head:  .res 1               ; written by the NMI
key_tail:  .res 1               ; written by the foreground

.segment "CODE"

; key_init -- clear the key state and the queue.
; Clobbers: A
key_init:
  lda #0
  sta key_prev
  sta key_prev+1
  sta key_cnt
  sta key_cnt+1
  sta key_state
  sta key_state+1
  sta key_head
  sta key_tail
  rts

; key_nmi -- NMI part: sample and debounce the bank selected by Q7.
; In:  disp_phase = current common ($00 = bank 0, $FF = bank 1)
; Clobbers: A, X, Y, nmi_t0..2
key_nmi:
  ; Collect the 8 keys, key n in bit n, 1 = released.
  .repeat 8, i
    lda HW_KEYS + 7 - i
    asl a                       ; C = bit 7
    rol nmi_t0
  .endrepeat
  lda nmi_t0
  eor #$FF                      ; 1 = pressed
  ldx #0
  bit disp_phase
  bpl @bank
  inx
@bank:
  cmp key_prev,x
  beq @same
  sta key_prev,x
  stz key_cnt,x
  rts
@same:
  ldy key_cnt,x
  cpy #KEY_DEBOUNCE
  bcs @done                     ; stable, already handled
  iny
  tya
  sta key_cnt,x
  cpy #KEY_DEBOUNCE
  bne @done
  lda key_prev,x
  eor key_state,x
  beq @done
  sta nmi_t0                    ; changed keys
  lda key_prev,x
  sta key_state,x
  sta nmi_t1                    ; new state
  txa
  asl a
  asl a
  asl a
  sta nmi_t2                    ; key code of bit 0
@event:
  lsr nmi_t1                    ; C = new state of this key
  lda nmi_t2
  bcs @pressed
  ora #KEY_RELEASED
@pressed:
  lsr nmi_t0                    ; C = key changed
  bcc @next
  ldy key_head
  sta key_q,y
  iny
  tya
  and #KEY_QSIZE - 1
  cmp key_tail
  beq @next                     ; queue full: drop the event
  sta key_head
@next:
  inc nmi_t2
  lda nmi_t0
  bne @event
@done:
  rts

; key_get -- next key event.
; Out: C = 1: A = event (key code, bit 7 = released). C = 0: no event.
; Clobbers: A, X
key_get:
  ldx key_tail
  cpx key_head
  beq @none
  lda key_q,x
  pha
  inx
  txa
  and #KEY_QSIZE - 1
  sta key_tail
  pla
  sec
  rts
@none:
  clc
  rts

; key_flush -- discard all pending key events.
; Clobbers: A
key_flush:
  lda key_head
  sta key_tail
  rts

; key_down -- debounced state of one key.
; In:  A = key code (0..15)
; Out: C = 1 pressed, C = 0 released
; Clobbers: A, X, Y
key_down:
  tay
  and #7
  tax
  lda hal_bit,x
  pha
  tya
  lsr a
  lsr a
  lsr a
  and #1
  tax
  pla
  and key_state,x
  cmp #1
  rts
