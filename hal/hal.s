; SPDX-License-Identifier: MIT
; hal/hal.s -- HAL initialisation and the HAL part of the NMI handler.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"

.importzp disp_count, disp_hold
.exportzp nmi_t0, nmi_t1, nmi_t2

.segment "HALZP": zeropage

nmi_t0: .res 1                  ; scratch for the NMI parts (key_nmi, brd_nmi)
nmi_t1: .res 1
nmi_t2: .res 1

.segment "CODE"

; hal_init -- initialise all HAL modules. Called by the runtime once,
; with zero page and page 2 cleared, before the full NMI handler is
; enabled.
; In:  disp_buf = initial display content
; Clobbers: A, X, Y
hal_init:
  ldx #HW_Q_SPEAKER
  stz HW_LATCH,x                ; speaker off
  lda #0
  jsr mled_set
  jsr key_init
  jsr brd_init
  jmp disp_init

; hal_nmi -- HAL work of one NMI tick (runtime/nmi.s). Worst case
; measured in docs/hal-api.md. Ticks are split so that key events and
; board events never fall into the same tick:
;   LCD_AC_TICKS - 1 of LCD_AC_TICKS ticks: board sensors of one rank
;                                           (events), LEDs of the next
;   every LCD_AC_TICKS-th tick:  board LEDs of the next rank, keys of the
;                                current bank (events), LCD common toggle
; Clobbers: A, X, Y, nmi_t0..2
hal_nmi:
  dec disp_count
  beq @key_tick
  jmp brd_nmi
@key_tick:
  lda disp_hold                 ; display buffer being rebuilt (disp_lock):
  beq @refresh                  ; treat this as a plain board tick and
  inc disp_count                ; retry the refresh on the next tick
  jmp brd_nmi
@refresh:
  lda #LCD_AC_TICKS
  sta disp_count
  jsr brd_nmi_leds
  jsr key_nmi                   ; before the toggle: Q7 = this bank since 8 ms
  jmp disp_nmi
