; SPDX-License-Identifier: MIT
; hal/cart.s -- opening library cartridge slot $4000-$7FFF.
;
; The known cartridges (HG 440 for MM IV, HG 550 for MM V) carry no
; identifier (docs/hardware.md, section 7). cart_check therefore uses a
; plausibility rule for presence and the CRC-32 for identification:
;   - two CRC passes over the slot must agree (open bus is not stable),
;   - every 256-byte page has at least CART_MIN_DISTINCT distinct values
;     (an empty slot may read a constant value),
;   - every page has at most CART_MAX_ADDRHI bytes equal to its address
;     high byte (open bus returns the last byte on the data bus, which
;     is the address high byte for LDA (zp)).

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"

.import hal_bit

CRC_HG440 = $81FFCDFD           ; HG 440
CRC_HG550 = $0359F13D           ; HG 550

.segment "HALBSS"

cart_seen:  .res 32             ; one bit per byte value
cart_crc1:  .res 4              ; CRC of the first pass
cart_dist:  .res 1              ; distinct values in this page
cart_eq:    .res 1              ; bytes equal to the page number

.segment "CODE"

; cart_check -- detect and identify a cartridge.
; Out: A = CART_NONE, CART_UNKNOWN, CART_HG440 or CART_HG550;
;      crc_val = CRC-32 over $4000-$7FFF (second pass)
; Takes about 1 s.
; Clobbers: A, X, Y, hal_p0, hal_p1
cart_check:
  ; Two CRC passes.
  jsr cart_crc
  ldx #3
@save:
  lda crc_val,x
  sta cart_crc1,x
  dex
  bpl @save
  jsr cart_crc
  ldx #3
@cmp:
  lda crc_val,x
  cmp cart_crc1,x
  bne @none
  dex
  bpl @cmp

  ; Plausibility per page.
  stz hal_p0
  lda #>HW_CART
  sta hal_p0+1
@page:
  ldx #31
@clear:
  stz cart_seen,x
  dex
  bpl @clear
  stz cart_dist
  stz cart_eq
  ldy #0
@byte:
  lda (hal_p0),y
  cmp hal_p0+1
  bne @not_eq
  inc cart_eq
@not_eq:
  pha
  and #7
  tax
  lda hal_bit,x
  sta hal_p1                    ; bit mask
  pla
  lsr a
  lsr a
  lsr a
  tax
  lda cart_seen,x
  bit hal_p1
  bne @known
  ora hal_p1
  sta cart_seen,x
  inc cart_dist
@known:
  iny
  bne @byte
  lda cart_dist
  cmp #CART_MIN_DISTINCT
  bcc @none
  lda cart_eq
  cmp #CART_MAX_ADDRHI + 1
  bcs @none
  inc hal_p0+1
  lda hal_p0+1
  cmp #>(HW_CART + HW_CART_SIZE)
  bne @page

  ; Identify.
  ldx #3
@hg440:
  lda crc_val,x
  cmp crc_known,x
  bne @try550
  dex
  bpl @hg440
  lda #CART_HG440
  rts
@try550:
  ldx #3
@hg550:
  lda crc_val,x
  cmp crc_known+4,x
  bne @unknown
  dex
  bpl @hg550
  lda #CART_HG550
  rts
@unknown:
  lda #CART_UNKNOWN
  rts
@none:
  lda #CART_NONE
  rts

; CRC-32 over the whole slot.
cart_crc:
  jsr crc_init
  stz hal_p0
  lda #>HW_CART
  sta hal_p0+1
  stz hal_p1
  lda #>HW_CART_SIZE
  sta hal_p1+1
  jsr crc_block
  jmp crc_final

.segment "RODATA"

crc_known:
  .dword CRC_HG440
  .dword CRC_HG550
