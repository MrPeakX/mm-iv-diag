; SPDX-License-Identifier: MIT
; runtime/vectors.s -- 6502 CPU vectors at $FFFA.

.import nmi, reset, irq

.segment "VECTORS"

  .word nmi                     ; $FFFA NMI, 600 Hz
  .word reset                   ; $FFFC RESET
  .word irq                     ; $FFFE IRQ/BRK (IRQ line tied to VSS)
