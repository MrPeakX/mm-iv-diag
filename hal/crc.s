; SPDX-License-Identifier: MIT
; hal/crc.s -- CRC-32 (IEEE 802.3, as zip uses), table driven.
;
; Usage: crc_init, then crc_byte / crc_block as often as needed, then
; crc_final; the result is in crc_val (little endian). The tables (4 x
; 256 bytes) are computed at assembly time. About 60 cycles per byte in
; crc_block: 32 KiB take about 0.4 s.

.include "hal.inc"

.segment "HALZP": zeropage

crc_val: .res 4                 ; CRC register, little endian

.segment "CODE"

; crc_init -- start a new CRC.
; Clobbers: A
crc_init:
  lda #$FF
  sta crc_val
  sta crc_val+1
  sta crc_val+2
  sta crc_val+3
  rts

; crc_final -- finish the CRC: crc_val = CRC-32.
; Clobbers: A, X
crc_final:
  ldx #3
@inv:
  lda crc_val,x
  eor #$FF
  sta crc_val,x
  dex
  bpl @inv
  rts

; crc_byte -- add one byte.
; In:  A = byte
; Clobbers: A, X
crc_byte:
  eor crc_val
  tax
  lda crc_val+1
  eor crc_t0,x
  sta crc_val
  lda crc_val+2
  eor crc_t1,x
  sta crc_val+1
  lda crc_val+3
  eor crc_t2,x
  sta crc_val+2
  lda crc_t3,x
  sta crc_val+3
  rts

; crc_block -- add a memory block.
; In:  hal_p0 = start address, hal_p1 = length in bytes (0 = nothing)
; Out: hal_p0 = end address + 1, hal_p1 = 0
; Clobbers: A, X
crc_block:
  lda hal_p1
  ora hal_p1+1
  beq @done
@byte:
  lda (hal_p0)
  eor crc_val
  tax
  lda crc_val+1
  eor crc_t0,x
  sta crc_val
  lda crc_val+2
  eor crc_t1,x
  sta crc_val+1
  lda crc_val+3
  eor crc_t2,x
  sta crc_val+2
  lda crc_t3,x
  sta crc_val+3
  inc hal_p0
  bne @count
  inc hal_p0+1
@count:
  lda hal_p1
  bne @low
  dec hal_p1+1
@low:
  dec hal_p1
  bne @byte
  lda hal_p1+1
  bne @byte
@done:
  rts

.segment "RODATA"

; CRC-32 table, reflected polynomial $EDB88320, split into 4 tables of
; the bytes 0..3 of each entry. Computed in 16-bit halves (lo, hi) so
; that no intermediate value exceeds 16 bits.
.macro CRC_TABLE byte
  .repeat 256, i
    .scope
      lo .set i
      hi .set 0
      .repeat 8
        lsb .set lo & 1
        lo .set ((lo >> 1) | ((hi & 1) << 15)) ^ (lsb * $8320)
        hi .set (hi >> 1) ^ (lsb * $EDB8)
      .endrepeat
      .if byte = 0
        .byte <lo
      .elseif byte = 1
        .byte >lo
      .elseif byte = 2
        .byte <hi
      .else
        .byte >hi
      .endif
    .endscope
  .endrepeat
.endmacro

crc_t0: CRC_TABLE 0
crc_t1: CRC_TABLE 1
crc_t2: CRC_TABLE 2
crc_t3: CRC_TABLE 3
