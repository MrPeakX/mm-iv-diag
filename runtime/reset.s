; SPDX-License-Identifier: MIT
; runtime/reset.s -- power-on and reset sequence (docs/boot.md).
;
; 1. CPU and output init, banner on the display (no RAM).
; 2. Pre-RAM test of zero page and stack page, registers only: no JSR,
;    no stack, no RAM variables. NMIs keep arriving and push 4 bytes
;    (CPU 3, handler PHA 1) below S, so the stack page is tested in two
;    halves with S in the other half.
; 3. Address-line test, March U of page 2, HAL init, NMI handler on,
;    March U of $0300-$1FFF, RAM cleared.
; 4. Jump to the application (main).

.include "hw.inc"
.include "timing.inc"
.include "runtime.inc"
.macpack longbranch

.import main, app_banner
.import rt_prefont_lo, rt_prefont_hi, rt_lcd_xor
.import hal_init
.importzp disp_buf

.segment "CODE"

; ---------------------------------------------------------------------------
; Pre-RAM March U over base+lo .. base+hi (one page), background bg.
; Registers only. On failure jumps to fail with X = address low byte,
; Y = failing bits.
; ---------------------------------------------------------------------------

.macro PRE_MARCH base, lo, hi, bg, fail
  .local m0, m1, m2, m3, m4, n0, n1, n2, n3, f0, f1, done
  ; M0: w0
  ldx #lo
m0:
  lda #bg
  sta base,x
  cpx #hi
  beq n0
  inx
  bra m0
  ; M1: up (r0, w1, r1, w0)
n0:
  ldx #lo
m1:
  lda base,x
  cmp #bg
  jne f0
  lda #(bg ^ $FF)
  sta base,x
  lda base,x
  cmp #(bg ^ $FF)
  jne f1
  lda #bg
  sta base,x
  cpx #hi
  beq n1
  inx
  bra m1
  ; M2: up (r0, w1)
n1:
  ldx #lo
m2:
  lda base,x
  cmp #bg
  jne f0
  lda #(bg ^ $FF)
  sta base,x
  cpx #hi
  beq n2
  inx
  bra m2
  ; M3: down (r1, w0, r0, w1)
n2:
  ldx #hi
m3:
  lda base,x
  cmp #(bg ^ $FF)
  jne f1
  lda #bg
  sta base,x
  lda base,x
  cmp #bg
  jne f0
  lda #(bg ^ $FF)
  sta base,x
  cpx #lo
  beq n3
  dex
  bra m3
  ; M4: down (r1, w0)
n3:
  ldx #hi
m4:
  lda base,x
  cmp #(bg ^ $FF)
  jne f1
  lda #bg
  sta base,x
  cpx #lo
  beq done
  dex
  bra m4
f0:
  eor #bg
  tay
  jmp fail
f1:
  eor #(bg ^ $FF)
  tay
  jmp fail
done:
.endmacro

; ---------------------------------------------------------------------------
; Reset entry
; ---------------------------------------------------------------------------

reset:
  sei                           ; IRQ line is tied to VSS: never CLI
  cld
  ldx #$FF
  txs

  ; Outputs are undefined after power-on.
  ldx #7
@latch:
  stz HW_LATCH,x                ; Q0-Q7 = 0: module LEDs, speaker, common
  dex
  bpl @latch
  lda #$FF
  sta HW_BOARD_MUX              ; mux active low, $FF = no rank
  stz HW_LED_DATA

  ; Banner with Q7 = 0 (visible = data). DC for the few ms until the NMI
  ; handler takes over is harmless.
  ldx #0
@banner:
  lda app_banner,x
  eor rt_lcd_xor,x
  sta HW_LCD
  inx
  cpx #HW_LCD_DIGITS
  bne @banner

  ; Zero page. The early NMI handler only reads nmi_magic.
  PRE_MARCH $0000, $00, $FF, $00, prefail_zp
  PRE_MARCH $0000, $00, $FF, $55, prefail_zp

  ; Stack page, lower half, NMI pushes go to $01FC-$01FF.
  PRE_MARCH $0100, $00, $7F, $00, prefail_stack
  PRE_MARCH $0100, $00, $7F, $55, prefail_stack
  ; Upper half, NMI pushes go to $017C-$017F.
  ldx #$7F
  txs
  PRE_MARCH $0100, $80, $FF, $00, prefail_stack
  PRE_MARCH $0100, $80, $FF, $55, prefail_stack
  ldx #$FF
  txs

  ; Zero page and stack are usable from here.
  jsr addr_test
  bcc @addr_ok
  lda #RT_E_ADDR
  jmp rt_fatal
@addr_ok:

  ; Page 2 holds runtime/HAL buffers: test it before the HAL starts.
  lda #$02
  ldx #$02
  ldy #$00
  jsr rt_march_u
  jcs ram_fail
  lda #$02
  ldx #$02
  ldy #$55
  jsr rt_march_u
  jcs ram_fail

  ; Clear zero page and page 2.
  ldx #0
@clear:
  stz $00,x
  stz $0200,x
  inx
  bne @clear

  ; HAL init, then enable the full NMI handler (second byte first).
  ldx #HW_LCD_DIGITS - 1
@buf:
  lda app_banner,x
  sta disp_buf,x
  dex
  bpl @buf
  jsr hal_init
  lda #NMI_MAGIC1
  sta nmi_magic+1
  lda #NMI_MAGIC0
  sta nmi_magic

  ; Application RAM, with the NMI handler running.
  lda #$03
  ldx #$1F
  ldy #$00
  jsr rt_march_u
  bcs ram_fail
  lda #$03
  ldx #$1F
  ldy #$55
  jsr rt_march_u
  bcs ram_fail

  ; Clear $0300-$1FFF.
  stz rt_mt_ptr
  lda #$03
  sta rt_mt_ptr+1
  ldy #0
@clear_app:
  lda #0
@clear_page:
  sta (rt_mt_ptr),y
  iny
  bne @clear_page
  inc rt_mt_ptr+1
  lda rt_mt_ptr+1
  cmp #>HW_RAM_SIZE
  bne @clear_app

  jmp main

ram_fail:
  lda #RT_E_RAM
  jmp rt_fatal

; ---------------------------------------------------------------------------
; addr_test -- RAM address lines A0-A12.
; Writes a distinct value to $0000 and to each 1 << n (n = 0..12), $0000
; last, then reads all back. A line stuck or shorted makes two of these
; cells alias, so a cell reads the value of another one; the first cell
; that differs is reported. Uses only rt_mt_ptr ($06/$07, not a tested
; address).
; Out: C = 0 passed. C = 1 failed: rt_err_word = address,
;      rt_err_data = value read.
; Clobbers: A, X
; ---------------------------------------------------------------------------

ADDR_VALUE = $11                ; value of line n is ADDR_VALUE + n
ADDR_ZERO  = $10                ; value of $0000

addr_test:
  ldx #0
@write:
  lda addr_lo,x
  sta rt_mt_ptr
  lda addr_hi,x
  sta rt_mt_ptr+1
  txa
  clc
  adc #ADDR_VALUE
  sta (rt_mt_ptr)
  inx
  cpx #13
  bne @write
  lda #ADDR_ZERO
  sta $00

  ldx #0
@check:
  lda addr_lo,x
  sta rt_mt_ptr
  lda addr_hi,x
  sta rt_mt_ptr+1
  txa
  clc
  adc #ADDR_VALUE
  cmp (rt_mt_ptr)
  bne @fail
  inx
  cpx #13
  bne @check
  stz rt_mt_ptr
  stz rt_mt_ptr+1
  lda $00
  cmp #ADDR_ZERO
  bne @fail_zero
  clc
  rts
@fail:
  lda (rt_mt_ptr)
@fail_zero:
  sta rt_err_data
  lda rt_mt_ptr
  sta rt_err_word
  lda rt_mt_ptr+1
  sta rt_err_word+1
  sec
  rts

; ---------------------------------------------------------------------------
; Pre-RAM failure loops: no RAM. X = address low byte, Y = failing bits.
; Display "aa.bb" (zero page) or "aa:bb" (stack page) with AC drive, and
; a ~950 Hz tone during every second half period (heard as a buzz).
; ---------------------------------------------------------------------------

.macro PRE_WRITE invert, dp0, dp2
  lda rt_prefont_lo,y
  ora #dp0
  eor #(invert ^ LCD_XOR_DIGIT0)
  sta HW_LCD
  lda rt_prefont_hi,y
  eor #(invert ^ LCD_XOR_DIGIT1)
  sta HW_LCD
  lda rt_prefont_lo,x
  ora #dp2
  eor #(invert ^ LCD_XOR_DIGIT2)
  sta HW_LCD
  lda rt_prefont_hi,x
  eor #(invert ^ LCD_XOR_DIGIT3)
  sta HW_LCD
.endmacro

.macro PREFAIL dp0, dp2
  .local loop
loop:
  PRE_WRITE $00, dp0, dp2       ; data first, then common (see disp_nmi)
  stz HW_LATCH + HW_Q_COMMON
  stz HW_LATCH + HW_Q_SPEAKER
  .repeat FATAL_DELAY_OUTER
    lda #0
:   dec a
    bne :-
  .endrepeat
  PRE_WRITE $FF, dp0, dp2
  lda #HW_LATCH_ON
  sta HW_LATCH + HW_Q_COMMON
  .repeat FATAL_DELAY_OUTER, i
    lda #((i & 2) << 6)
    sta HW_LATCH + HW_Q_SPEAKER
    lda #0
:   dec a
    bne :-
  .endrepeat
  jmp loop
.endmacro

prefail_zp:
  PREFAIL $00, HW_SEG_DP        ; DP after digit 2: "aa.bb"
prefail_stack:
  PREFAIL HW_SEG_DP, $00        ; colon (digit 0 bit 7): "aa:bb"

.segment "RODATA"

addr_lo:
  .repeat 13, n
    .byte .lobyte(1 << n)
  .endrepeat
addr_hi:
  .repeat 13, n
    .byte .hibyte(1 << n)
  .endrepeat
