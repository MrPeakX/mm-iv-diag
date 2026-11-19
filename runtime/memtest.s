; SPDX-License-Identifier: MIT
; runtime/memtest.s -- March U RAM test over whole pages.
;
; March U (van de Goor): {B(w0); U(r0,w1,r1,w0); U(r0,w1); D(r1,w0,r0,w1);
; D(r1,w0)}, U = ascending, D = descending addresses, 0 = background,
; 1 = its complement. 13 operations per byte, about 150 cycles per byte.
; Detects stuck-at, transition, address decoder and most coupling faults.

.include "runtime.inc"
.macpack longbranch

.segment "CODE"

; rt_march_u -- test pages A..X (inclusive) with background Y.
; In:  A = first page, X = last page (>= A), Y = background byte.
; Out: C = 0 passed. C = 1 failed: rt_err_word = address,
;      rt_err_data = failing bits (value read XOR expected).
;      Memory is left filled with the background.
; Clobbers: A, X, Y, rt_mt_*.
; Must not cover the stack in use or ZP $00-$17.
rt_march_u:
  sta rt_mt_first
  stx rt_mt_last
  sty rt_mt_bg
  tya
  eor #$FF
  sta rt_mt_bgc
  stz rt_mt_ptr

  ; M0: any order (w0)
  jsr first_page
@m0:
  lda rt_mt_bg
  sta (rt_mt_ptr),y
  iny
  bne @m0
  jsr next_page
  bcc @m0

  ; M1: up (r0, w1, r1, w0)
  jsr first_page
@m1:
  lda (rt_mt_ptr),y
  cmp rt_mt_bg
  jne fail0
  lda rt_mt_bgc
  sta (rt_mt_ptr),y
  lda (rt_mt_ptr),y
  cmp rt_mt_bgc
  jne fail1
  lda rt_mt_bg
  sta (rt_mt_ptr),y
  iny
  bne @m1
  jsr next_page
  bcc @m1

  ; M2: up (r0, w1)
  jsr first_page
@m2:
  lda (rt_mt_ptr),y
  cmp rt_mt_bg
  jne fail0
  lda rt_mt_bgc
  sta (rt_mt_ptr),y
  iny
  bne @m2
  jsr next_page
  bcc @m2

  ; M3: down (r1, w0, r0, w1)
  jsr last_page
@m3:
  lda (rt_mt_ptr),y
  cmp rt_mt_bgc
  jne fail1
  lda rt_mt_bg
  sta (rt_mt_ptr),y
  lda (rt_mt_ptr),y
  cmp rt_mt_bg
  jne fail0
  lda rt_mt_bgc
  sta (rt_mt_ptr),y
  dey
  cpy #$FF
  bne @m3
  jsr prev_page
  bcc @m3

  ; M4: down (r1, w0)
  jsr last_page
@m4:
  lda (rt_mt_ptr),y
  cmp rt_mt_bgc
  bne fail1
  lda rt_mt_bg
  sta (rt_mt_ptr),y
  dey
  cpy #$FF
  bne @m4
  jsr prev_page
  bcc @m4

  clc
  rts

fail0:
  eor rt_mt_bg
  bra fail
fail1:
  eor rt_mt_bgc
fail:
  sta rt_err_data
  sty rt_err_word
  lda rt_mt_ptr+1
  sta rt_err_word+1
  sec
  rts

; Set the pointer to the first page, Y = 0.
first_page:
  lda rt_mt_first
  sta rt_mt_ptr+1
  ldy #0
  rts

; Set the pointer to the last page, Y = $FF.
last_page:
  lda rt_mt_last
  sta rt_mt_ptr+1
  ldy #$FF
  rts

; Advance one page up. C = 1 when the last page is done. Y stays 0.
next_page:
  lda rt_mt_ptr+1
  cmp rt_mt_last
  bcs @done
  inc rt_mt_ptr+1
  clc
  rts
@done:
  sec
  rts

; Advance one page down. C = 1 when the first page is done. Y stays $FF.
prev_page:
  lda rt_mt_ptr+1
  cmp rt_mt_first
  beq @done
  bcc @done
  dec rt_mt_ptr+1
  clc
  rts
@done:
  sec
  rts
