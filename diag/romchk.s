; SPDX-License-Identifier: MIT
; diag/romchk.s -- ROM check: CRC-32 of each 4 KiB block against the
; block CRC table in the ident block (include/ident.inc, written by
; tools/romtool.pl). The CRC area of the ident block is taken as zero.
; A bad block mask tells where the ROM is wrong: one block points to the
; chip or its programming, a pattern of blocks to an address line (A12:
; $AA or $55, A13: $CC or $33, A14: $F0 or $0F), all blocks to a data
; line or the access timing (docs/codes.md).

.include "hal.inc"
.include "ident.inc"
.include "ui.inc"

.segment "ZEROPAGE"

rc_mask: .res 1                 ; bad block mask

BLOCK_BASE = IDENT_BASE         ; the ROM starts with the ident block

.segment "CODE"

; rom_check -- check all ROM blocks.
; Out: A = bad block mask (bit n = block $8000 + n * $1000), Z = 1: ROM good
; Takes about 0.4 s.
; Clobbers: A, X, Y, hal_p0, hal_p1, crc_val
rom_check:
  stz rc_mask
  ldy #0                        ; block number
@block:
  phy
  jsr crc_init
  tya
  asl a
  asl a
  asl a
  asl a
  clc
  adc #>BLOCK_BASE
  sta hal_p0+1
  stz hal_p0
  cpy #0
  bne @plain
  ; Block 0: up to the CRC area, zeros, after the CRC area.
  LDPTR hal_p1, IDENT_CRC_AREA
  jsr crc_block
  ldy #IDENT_CRC_AREA_LEN
@zero:
  lda #0
  jsr crc_byte
  dey
  bne @zero
  LDPTR hal_p0, BLOCK_BASE + IDENT_CRC_AREA + IDENT_CRC_AREA_LEN
  LDPTR hal_p1, IDENT_BLOCK_SIZE - IDENT_CRC_AREA - IDENT_CRC_AREA_LEN
  bra @rest
@plain:
  LDPTR hal_p1, IDENT_BLOCK_SIZE
@rest:
  jsr crc_block
  jsr crc_final
  ply
  ; Compare with the table entry.
  tya
  asl a
  asl a
  tax
  lda crc_val
  cmp IDENT_BASE + IDENT_BCRC,x
  bne @bad
  lda crc_val+1
  cmp IDENT_BASE + IDENT_BCRC + 1,x
  bne @bad
  lda crc_val+2
  cmp IDENT_BASE + IDENT_BCRC + 2,x
  bne @bad
  lda crc_val+3
  cmp IDENT_BASE + IDENT_BCRC + 3,x
  beq @next
@bad:
  lda bit_of,y
  ora rc_mask
  sta rc_mask
@next:
  iny
  cpy #IDENT_BLOCKS
  bne @block
  lda rc_mask
  rts

.segment "RODATA"

bit_of: .byte $01, $02, $04, $08, $10, $20, $40, $80
