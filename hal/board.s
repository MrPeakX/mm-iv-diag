; SPDX-License-Identifier: MIT
; hal/board.s -- sensor board and module LEDs (latch Q0-Q5).
;
; Board hardware (docs/hardware.md, section 6): $2800 selects ranks
; (active low), $2400 lights files in the selected ranks, $3000 reads the
; sensors of the selected ranks (active low). LED refresh and sensor scan
; share the multiplexer, so brd_nmi does both, one rank per tick:
;   1. read the sensors of the rank selected since the previous tick,
;   2. LED data off (no ghosting on the next rank), select the next rank,
;   3. write that rank's LED data.
; Each rank is lit 1/8 of the time; a full scan takes 8 ticks (75 Hz).
;
; Debounce: a rank's sample is accepted when BRD_DEBOUNCE further scans
; are equal to it. The first accepted sample of each rank after brd_init
; sets the state without events; every later change of a field puts an
; event into a queue: field number (a1 = 0 ... h8 = 63), bit 7 set when a
; piece was placed. The queue holds BRD_QSIZE - 1 events; more are
; dropped.
;
; Field numbers: field = 8 * rank_index + file_index (include/hal.inc).
; brd_state, brd_led and brd_blink are 8-byte bitmaps, byte = rank
; index, bit = file index; the application may read them directly.

.include "hw.inc"
.include "timing.inc"
.include "hal.inc"

.importzp nmi_t0, nmi_t1, nmi_t2
.export hal_bit

BRD_QSIZE = 32                  ; power of two

.segment "HALBSS"

brd_state:  .res 8              ; debounced sensors, 1 = piece
brd_led:    .res 8              ; field LEDs, 1 = on
brd_blink:  .res 8              ; field LEDs, 1 = blinking (with brd_led set)
brd_prev:   .res 8              ; last raw sample per rank, 1 = piece
brd_cnt:    .res 8              ; equal scans since the last change
brd_q:      .res BRD_QSIZE      ; event queue
brd_head:   .res 1              ; written by the NMI
brd_tail:   .res 1              ; written by the foreground
brd_primed: .res 1              ; bit r = rank r has a valid state
brd_rank:   .res 1              ; rank selected in the multiplexer
brd_bcnt:   .res 1              ; ticks until the next blink phase change
brd_boff:   .res 1              ; $FF = blinking LEDs are in their off phase
mled_shadow: .res 1             ; module LEDs, bit n = Qn

.segment "CODE"

; brd_init -- clear state, LEDs and queue; select rank 1.
; Clobbers: A, X
brd_init:
  stz HW_LED_DATA
  ldx #7
@clear:
  stz brd_state,x
  stz brd_led,x
  stz brd_blink,x
  stz brd_prev,x
  stz brd_cnt,x
  dex
  bpl @clear
  stz brd_head
  stz brd_tail
  stz brd_primed
  stz brd_rank
  stz brd_boff
  lda #BRD_BLINK_TICKS
  sta brd_bcnt
  lda #<~1
  sta HW_BOARD_MUX              ; rank 1 (mux active low)
  rts

; brd_nmi -- NMI part: sensors of one rank, then LEDs of the next rank.
; brd_nmi_leds -- NMI part without the sensors: LEDs of the next rank.
;   hal_nmi calls it on the ticks with the key scan, so that sensor and
;   key events never fall into the same tick (NMI budget); the rank
;   misses one sensor sample then, which only delays its debounce.
; Clobbers: A, X, Y, nmi_t0..2
brd_nmi_leds:
  ldx brd_rank
  bra brd_mux
brd_nmi:
  ldx brd_rank
  lda HW_SENSORS                ; 0 = piece
  eor #$FF
  cmp brd_prev,x
  beq @same
  sta brd_prev,x
  stz brd_cnt,x
  bra brd_mux
@same:
  ldy brd_cnt,x
  cpy #BRD_DEBOUNCE
  bcs brd_mux                   ; stable, already handled
  iny
  tya
  sta brd_cnt,x
  cpy #BRD_DEBOUNCE
  bne brd_mux
  lda hal_bit,x
  and brd_primed
  bne @changes
  ; First valid sample of this rank: take it without events.
  lda hal_bit,x
  ora brd_primed
  sta brd_primed
  lda brd_prev,x
  sta brd_state,x
  bra brd_mux
@changes:
  lda brd_prev,x
  eor brd_state,x
  beq brd_mux
  sta nmi_t0                    ; changed fields
  lda brd_prev,x
  sta brd_state,x
  sta nmi_t1                    ; new state
  txa
  asl a
  asl a
  asl a
  sta nmi_t2                    ; field of file a
@event:
  lsr nmi_t1                    ; C = piece on this field
  lda nmi_t2
  bcc @lifted
  ora #BRD_PLACED
@lifted:
  lsr nmi_t0                    ; C = field changed
  bcc @next
  ldy brd_head
  sta brd_q,y
  iny
  tya
  and #BRD_QSIZE - 1
  cmp brd_tail
  beq @next                     ; queue full: drop the event
  sta brd_head
@next:
  inc nmi_t2
  lda nmi_t0
  bne @event

brd_mux:
  ; Next rank: LEDs off, select, LED data of the new rank.
  stz HW_LED_DATA               ; LEDs off before the rank switch
  inx
  txa
  and #7
  sta brd_rank
  tax
  lda hal_nbit,x
  sta HW_BOARD_MUX              ; active low
  lda brd_blink,x
  and brd_boff
  eor #$FF
  and brd_led,x
  sta HW_LED_DATA

  ; Blink phase.
  dec brd_bcnt
  bne @done
  lda #BRD_BLINK_TICKS
  sta brd_bcnt
  lda brd_boff
  eor #$FF
  sta brd_boff
@done:
  rts

; brd_get -- next board event.
; Out: C = 1: A = event (field, bit 7 = placed). C = 0: no event.
; Clobbers: A, X
brd_get:
  ldx brd_tail
  cpx brd_head
  beq @none
  lda brd_q,x
  pha
  inx
  txa
  and #BRD_QSIZE - 1
  sta brd_tail
  pla
  sec
  rts
@none:
  clc
  rts

; brd_flush -- discard all pending board events.
; Clobbers: A
brd_flush:
  lda brd_head
  sta brd_tail
  rts

; field_split -- A = field (0..63) -> X = rank index, A = file bit mask.
; Clobbers: Y
field_split:
  tay
  and #7
  tax
  lda hal_bit,x
  pha
  tya
  lsr a
  lsr a
  lsr a
  and #7
  tax
  pla
  rts

; brd_piece -- debounced sensor state of one field.
; In:  A = field
; Out: C = 1 piece present, C = 0 empty
; Clobbers: A, X, Y
brd_piece:
  jsr field_split
  and brd_state,x
  cmp #1
  rts

; brd_led_set -- field LED on (steady).
; brd_led_blink -- field LED blinking.
; brd_led_clear -- field LED off.
; In:  A = field
; Clobbers: A, X, Y
brd_led_set:
  jsr field_split
  pha
  ora brd_led,x
  sta brd_led,x
  pla
  eor #$FF
  and brd_blink,x
  sta brd_blink,x
  rts

brd_led_blink:
  jsr field_split
  pha
  ora brd_led,x
  sta brd_led,x
  pla
  ora brd_blink,x
  sta brd_blink,x
  rts

brd_led_clear:
  jsr field_split
  eor #$FF
  pha
  and brd_led,x
  sta brd_led,x
  pla
  and brd_blink,x
  sta brd_blink,x
  rts

; brd_led_alloff -- all field LEDs off.
; brd_led_all -- all field LEDs on (steady).
; Clobbers: A, X
brd_led_alloff:
  lda #0
  bra led_fill
brd_led_all:
  lda #$FF
led_fill:
  ldx #7
@fill:
  sta brd_led,x
  stz brd_blink,x
  dex
  bpl @fill
  rts

; mled_set -- module LEDs (latch Q0-Q5).
; In:  A = bit n lights LED Qn (bits 6, 7 ignored)
; Clobbers: A, X
mled_set:
  and #$3F
  sta mled_shadow
  ldx #0
@q:
  lsr a
  pha
  lda #HW_LATCH_OFF
  bcc @write
  lda #HW_LATCH_ON
@write:
  sta HW_LATCH,x                ; D7 = new output value
  pla
  inx
  cpx #HW_Q_LED5 + 1
  bne @q
  rts

; mled_get -- current module LED state.
; Out: A = bit n = LED Qn
; Clobbers: -
mled_get:
  lda mled_shadow
  rts

.segment "RODATA"

hal_bit:  .byte $01, $02, $04, $08, $10, $20, $40, $80
hal_nbit: .byte $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F
