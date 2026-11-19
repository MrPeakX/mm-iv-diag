; SPDX-License-Identifier: MIT
; diag/rpc.s -- test hook: lets an external test call any routine.
;
; The application calls rpc_poll from its main loop. A test writes the
; routine address to rpc_addr, the register values to rpc_a/x/y, then a
; nonzero value to rpc_flag. rpc_poll calls the routine with these
; registers and stores the registers and flags it returns, then clears
; rpc_flag. The routine runs in the foreground with the NMI handler
; active, exactly as when the application calls it.
;
; rpc_hold nonzero stops the application (idle display, key clicks)
; while it waits in its main loop: the test owns the display, the event
; queues and the speaker, and only rpc_poll keeps running.
;
; RAM is cleared at boot, so the hook is inert unless a test uses it.
; Addresses: ld65 label file (build/*.lbl).

.export rpc_poll
.exportzp rpc_flag, rpc_addr, rpc_a, rpc_x, rpc_y, rpc_p, rpc_hold

; Zero page: the RAM test (test 6) destroys $0300-$1FFF.
.segment "ZEROPAGE"

rpc_flag: .res 1                ; nonzero: call requested
rpc_addr: .res 2                ; routine to call
rpc_a:    .res 1                ; A in / out
rpc_x:    .res 1                ; X in / out
rpc_y:    .res 1                ; Y in / out
rpc_p:    .res 1                ; P out
rpc_hold: .res 1                ; nonzero: application paused, test owns the HAL

.segment "CODE"

; rpc_poll -- perform a requested call.
; Clobbers: A, X, Y (and whatever the called routine clobbers)
rpc_poll:
  lda rpc_flag
  beq @done
  lda rpc_a
  ldx rpc_x
  ldy rpc_y
  jsr @call
  php
  sta rpc_a
  stx rpc_x
  sty rpc_y
  pla
  sta rpc_p
  stz rpc_flag
@done:
  rts
@call:
  jmp (rpc_addr)

.segment "RODATA"

; Every public HAL routine, so that the linker pulls all HAL modules
; from hal.lib and tests can call them through this hook even where the
; application does not use them yet.
.include "hal.inc"
rpc_hal_table:
  .addr disp_clear, disp_raw, disp_set4, disp_hex8, disp_hex16, disp_dec
  .addr disp_str, disp_str_to, disp_fill
  .addr key_get, key_down, key_flush
  .addr brd_get, brd_flush, brd_piece, brd_led_set, brd_led_clear
  .addr brd_led_blink, brd_led_alloff, brd_led_all, mled_set, mled_get
  .addr snd_tone, snd_beep_ok, snd_beep_err, snd_click
  .addr tmr_read, tmr_wait
  .addr crc_init, crc_byte, crc_block, crc_final
  .addr cart_check
