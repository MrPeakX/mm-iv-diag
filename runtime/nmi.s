; SPDX-License-Identifier: MIT
; runtime/nmi.s -- NMI (600 Hz time base) and IRQ/BRK handlers.
;
; The NMI cannot be disabled and starts at power-on (74HC4060,
; clock / 8192). Until the boot code stores NMI_MAGIC0/1 in
; nmi_magic, the handler only returns; it reads nothing else and writes
; only the stack (3 bytes by the CPU, 1 by PHA) and HW_NMI_ACK.
;
; Every NMI first writes HW_NMI_ACK ($3800). It is not connected on the
; MM IV / MM V and has no effect, but some emulators raise the next NMI
; only after that write. STZ needs no register and no RAM, so it is safe
; in the early (pre-RAM) path too.

.include "hw.inc"
.include "runtime.inc"

.import hal_nmi
.export nmi_rti

.segment "CODE"

nmi:
  stz HW_NMI_ACK                ; see above
  pha
  lda nmi_magic
  cmp #NMI_MAGIC0
  bne nmi_early
  lda nmi_magic+1
  cmp #NMI_MAGIC1
  bne nmi_early
  phx
  phy
  cld                           ; CMOS parts clear D on interrupt; be explicit

  inc rt_ticks
  bne @ticked
  inc rt_ticks+1
  bne @ticked
  inc rt_ticks+2
  bne @ticked
  inc rt_ticks+3
@ticked:

  jsr hal_nmi                   ; display, keys, board (hal/hal.s)

  ply
  plx
nmi_early:
  pla
nmi_rti:
  rti

; IRQ/BRK. The IRQ line is permanently asserted (tied to VSS), so an IRQ
; only arrives after a CLI or an RTI/PLP that cleared I; returning would
; re-enter at once. Both cases are fatal.
irq:
  tsx
  lda HW_STACK+2,x              ; pushed PC low
  sta rt_err_word
  lda HW_STACK+3,x              ; pushed PC high
  sta rt_err_word+1
  lda HW_STACK+1,x              ; pushed P
  and #$10                      ; B flag: set by BRK only
  beq @irq
  ; BRK pushes the address of BRK + 2.
  lda rt_err_word
  sec
  sbc #2
  sta rt_err_word
  bcs @brk
  dec rt_err_word+1
@brk:
  lda #RT_E_BRK
  jmp rt_fatal
@irq:
  lda #RT_E_IRQ
  jmp rt_fatal
