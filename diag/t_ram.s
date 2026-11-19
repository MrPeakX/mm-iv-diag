; SPDX-License-Identifier: MIT
; diag/t_ram.s -- test 6: RAM and ROM, continuous loop until CL.
;
; One pass (about 1.3 s):
;   1. page 2 (runtime/HAL buffers): saved to $1F00, NMI handler paused
;      (early exit) for the ~32 ms of the test, restored;
;   2. $0300-$1FFF, March U with backgrounds $00 and $55;
;   3. ROM: CRC-32 of the 8 blocks of 4 KiB (diag/romchk.s).
; The zero page and the stack page hold the running program; they are
; tested at power-on only (docs/boot.md).
;
; Errors are counted, the loop goes on (an intermittent fault shows as a
; count). The display cycles through screens of T6_SCREEN_TICKS each
; (docs/codes.md):
;   "Pnnn"  passes completed (mod 10000)
;   after a RAM error:  "E-01", address, "b-bb" failing bits (last
;                       error), "cnnn" number of RAM errors
;   after a ROM error:  "E-03", "b-mm" bad block mask (last error),
;                       "cnnn" number of ROM errors
; Each new error sounds the error beep. The colon blinks (heartbeat).

.include "hal.inc"
.include "timing.inc"
.include "runtime.inc"
.include "ui.inc"

SCREENS   = 8
SAVE_PAGE = $1F00               ; page 2 is saved here during step 1

.segment "ZEROPAGE"

t6_pass:    .res 2              ; passes completed
t6_ram_n:   .res 2              ; RAM errors
t6_rom_n:   .res 2              ; ROM errors
t6_addr:    .res 2              ; last RAM error: address
t6_bits:    .res 1              ; last RAM error: failing bits
t6_mask:    .res 1              ; last ROM error: bad block mask
t6_scr:     .res 1              ; current screen
t6_next:    .res 2              ; tick of the next screen change

.segment "CODE"

test_ram:
  ldx #t6_next + 2 - t6_pass - 1
@clear:
  stz t6_pass,x
  dex
  bpl @clear
  jsr ui_heart_on
  jsr show_screen
  jsr next_time

@pass:
  ; 1. Page 2 with the HAL paused.
  stz nmi_magic                 ; NMI handler: early exit only
  ldx #0
@save:
  lda $0200,x
  sta SAVE_PAGE,x
  inx
  bne @save
  lda #$02
  ldx #$02
  ldy #$00
  jsr rt_march_u
  bcs @page2_done
  lda #$02
  ldx #$02
  ldy #$55
  jsr rt_march_u
@page2_done:
  php
  ldx #0
@restore:
  lda SAVE_PAGE,x
  sta $0200,x
  inx
  bne @restore
  lda #NMI_MAGIC0
  sta nmi_magic                 ; NMI_MAGIC1 was never touched
  plp
  jsr ram_result
  jsr t6_ui

  ; 2. Application RAM, two backgrounds.
  lda #$03
  ldx #>HW_RAM_SIZE - 1
  ldy #$00
  jsr rt_march_u
  jsr ram_result
  jsr t6_ui
  lda #$03
  ldx #>HW_RAM_SIZE - 1
  ldy #$55
  jsr rt_march_u
  jsr ram_result
  jsr t6_ui

  ; 3. ROM.
  jsr rom_check
  beq @rom_ok
  sta t6_mask
  inc t6_rom_n
  bne @rom_beep
  inc t6_rom_n+1
@rom_beep:
  jsr snd_beep_err
@rom_ok:
  ; Pass done (counter wraps at 10000).
  inc t6_pass
  bne @count
  inc t6_pass+1
@count:
  lda t6_pass
  cmp #<10000
  bne @shown
  lda t6_pass+1
  cmp #>10000
  bne @shown
  stz t6_pass
  stz t6_pass+1
@shown:
  lda t6_scr
  bne @ui
  jsr show_screen               ; new pass count
@ui:
  jsr t6_ui
  jmp @pass

; ram_result -- C = 1 from rt_march_u: count and keep the error.
ram_result:
  bcc @done
  lda rt_err_word
  sta t6_addr
  lda rt_err_word+1
  sta t6_addr+1
  lda rt_err_data
  sta t6_bits
  inc t6_ram_n
  bne @beep
  inc t6_ram_n+1
@beep:
  jsr snd_beep_err
@done:
  rts

; t6_ui -- serve keys (CL leaves), change the screen when due.
t6_ui:
  jsr ui_poll
  jsr tmr_read
  sec
  sbc t6_next
  txa
  sbc t6_next+1
  bmi @done
  jsr next_time
  ; Next screen that applies.
@advance:
  inc t6_scr
  lda t6_scr
  cmp #SCREENS
  bcc @check
  stz t6_scr
  bra @show
@check:
  cmp #5
  bcs @rom_screen
  lda t6_ram_n                  ; screens 1-4: RAM errors only
  ora t6_ram_n+1
  beq @advance
  bra @show
@rom_screen:
  lda t6_rom_n                  ; screens 5-7: ROM errors only
  ora t6_rom_n+1
  beq @advance
@show:
  jsr show_screen
@done:
  rts

next_time:
  jsr tmr_read
  clc
  adc #<T6_SCREEN_TICKS
  sta t6_next
  txa
  adc #>T6_SCREEN_TICKS
  sta t6_next+1
  rts

; show_screen -- draw screen t6_scr.
show_screen:
  lda t6_scr
  asl a
  tax
  jmp (screen_table,x)

scr_pass:
  lda t6_pass
  ldx t6_pass+1
  ldy #G_P
  jmp ui_show_num
scr_e01:
  LDPTR hal_p0, str_e01
  jmp disp_str
scr_addr:
  lda t6_addr
  ldx t6_addr+1
  jmp disp_hex16
scr_bits:
  lda t6_bits
  ldy #G_b
  jmp ui_hex_screen
scr_ram_n:
  lda t6_ram_n
  ldx t6_ram_n+1
  bra show_count
scr_e03:
  LDPTR hal_p0, str_e03
  jmp disp_str
scr_mask:
  lda t6_mask
  ldy #G_b
  jmp ui_hex_screen
scr_rom_n:
  lda t6_rom_n
  ldx t6_rom_n+1
show_count:
  ldy #G_c
  jmp ui_show_num

.segment "RODATA"

screen_table:
  .addr scr_pass, scr_e01, scr_addr, scr_bits, scr_ram_n
  .addr scr_e03, scr_mask, scr_rom_n

str_e01: .byte "E-01", 0
str_e03: .byte "E-03", 0
