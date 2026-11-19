; SPDX-License-Identifier: MIT
; include/hw.inc -- MM IV / MM V hardware constants.
;
; Registers, bits and protocols: docs/hardware.md (section numbers below).

.ifndef HW_INC
HW_INC = 1

; --- CPU and clock (section 1) --------------------------------------------

HW_CLOCK_HZ     = 4915200       ; 4.9152 MHz crystal
HW_NMI_DIVIDER  = 8192          ; 74HC4060: NMI every 8192 cycles
HW_NMI_HZ       = 600           ; HW_CLOCK_HZ / HW_NMI_DIVIDER

; --- Memory map (section 2) -----------------------------------------------

HW_RAM          = $0000         ; 8 KiB SRAM $0000-$1FFF
HW_RAM_SIZE     = $2000
HW_STACK        = $0100         ; 6502 stack page

HW_LCD          = $2000         ; LCD data shift register, mirror $03FF (W)
HW_LED_DATA     = $2400         ; board LED file data, mirror $03FF (W)
HW_BOARD_MUX    = $2800         ; board rank multiplexer, mirror $03FF (W)
HW_KEYS         = $2C00         ; keypad $2C00-$2C07, mirror $03F8 (R)
HW_SENSORS      = $3000         ; board sensors, mirror $03FF (R)
HW_LATCH        = $3400         ; 74HC259 latch $3400-$3407, mirror $03F8 (W)
HW_NMI_ACK      = $3800         ; not connected, mirror $03FF (W); written in
                                ; every NMI for emulators that re-arm the
                                ; NMI on this write

HW_CART        = $4000         ; cartridge slot $4000-$7FFF (R)
HW_CART_SIZE    = $4000
HW_ROM          = $8000         ; 32 KiB ROM $8000-$FFFF
HW_ROM_SIZE     = $8000

; --- Keypad (section 4) ---------------------------------------------------
; Read HW_KEYS + n; bit 7 = 0 when key n of the bank selected by Q7 is
; pressed. Only bit 7 is driven (74HCT251).

HW_KEY_MASK     = $80           ; key state in bit 7

; --- Output latch 74HC259 (section 5) -------------------------------------
; Write HW_LATCH + Qn; D7 is the new output value.

HW_LATCH_ON     = $80           ; D7 = 1
HW_LATCH_OFF    = $00           ; D7 = 0
HW_Q_LED0       = 0             ; Q0-Q5: module LEDs
HW_Q_LED5       = 5
HW_Q_SPEAKER    = 6             ; Q6: speaker (1 bit)
HW_Q_COMMON     = 7             ; Q7: LCD common and keypad bank

; --- LCD (section 3) ------------------------------------------------------
; Segment bits: a=0 b=1 c=2 d=3 e=4 f=5 g=6, bit 7 = decimal point
; (digits 3..1) or colon (digit 0). Visible pattern is
; data XOR (Q7 ? $FF : $00).

HW_SEG_A        = $01
HW_SEG_B        = $02
HW_SEG_C        = $04
HW_SEG_D        = $08
HW_SEG_E        = $10
HW_SEG_F        = $20
HW_SEG_G        = $40
HW_SEG_DP       = $80           ; DP of digits 3..1, colon on digit 0
HW_LCD_DIGITS   = 4             ; 4 x CD4015, 32-bit shift register

.endif
