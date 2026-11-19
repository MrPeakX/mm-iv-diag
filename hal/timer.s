; SPDX-License-Identifier: MIT
; hal/timer.s -- 600 Hz time base (rt_ticks, incremented by the NMI).
;
; rt_ticks (include/runtime.inc) is a 32-bit tick counter, 1 tick =
; 8192 CPU cycles = 1/600 s (docs/hardware.md, section 1). Multi-byte reads must
; be protected against a carry by the NMI between the byte reads.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"
.include "runtime.inc"

.segment "HALZP": zeropage

tmr_end: .res 2                 ; tmr_wait: end time

.segment "CODE"

; tmr_read -- low 16 bits of the tick counter, read consistently.
; Out: A = bits 0-7, X = bits 8-15
; Clobbers: -
tmr_read:
  lda rt_ticks
  ldx rt_ticks+1
  cmp rt_ticks                  ; NMI in between: read again
  bne tmr_read
  rts

; tmr_wait -- busy wait until the tick counter has advanced n times.
; In:  A = n low, X = n high (0..32767; MS_TICKS(ms) converts)
; Out: returns (n - 1)..n tick periods after the call (the first tick
;      may come at once)
; Clobbers: A, X
tmr_wait:
  sta tmr_end
  stx tmr_end+1
  jsr tmr_read
  clc
  adc tmr_end
  sta tmr_end
  txa
  adc tmr_end+1
  sta tmr_end+1
@wait:
  jsr tmr_read
  ; Done when now - end >= 0 (16-bit, signed).
  sec
  sbc tmr_end
  txa
  sbc tmr_end+1
  bmi @wait
  rts
