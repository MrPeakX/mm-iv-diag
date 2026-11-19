; SPDX-License-Identifier: MIT
; diag/t_keys.s -- test 3: keys. Every pressed key shows its code as
; "c-hh" (include/hal.inc KEY_*, docs/codes.md) with a click; CL leaves.
; The colon blinks while waiting (heartbeat).

.include "hal.inc"
.include "timing.inc"
.include "ui.inc"

.segment "CODE"

test_keys:
  lda #1
  sta ui_keys                   ; ui_wait returns the key presses
  lda #G_c
  sta disp_buf+3
  lda #G_DASH
  sta disp_buf+2
  sta disp_buf+1
  sta disp_buf
  jsr ui_heart_on
@wait:
  UI_WAIT $7FFF
  bcc @wait
  ldy #G_c
  jsr ui_hex_screen
  jsr snd_click
  bra @wait
