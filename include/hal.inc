; SPDX-License-Identifier: MIT
; include/hal.inc -- HAL API: zero-page registers, codes, routines.
;
; Calling convention (docs/hal-api.md):
; - Parameters in A, X, Y; pointers in the fixed zero-page registers
;   hal_p0 / hal_p1. Every routine documents inputs, outputs and the
;   registers it clobbers; registers not listed are preserved.
; - Flags are clobbered unless a routine returns a result in C.
; - Foreground routines may be called with the NMI handler running (the
;   normal case). None of them may be called from the NMI handler.

.ifndef HAL_INC
HAL_INC = 1

; --- Fixed zero-page registers (ZP_HAL, cfg/rom.cfg) ----------------------
; Pointer parameters. Callers may use them freely between HAL calls;
; a HAL routine that takes no pointer may still clobber them where noted.

hal_p0          = $18           ; 2 bytes: pointer parameter 0
hal_p1          = $1A           ; 2 bytes: pointer parameter 1

; --- Key codes (hal/keys.s) -----------------------------------------------
; code = 8 * bank + address offset (docs/hardware.md, section 4)

KEY_CL          = $00
KEY_POS         = $01
KEY_MEM         = $02
KEY_INFO        = $03
KEY_LEV         = $04
KEY_ENT         = $05
KEY_RIGHT       = $06           ; Right / White / 0
KEY_LEFT        = $07           ; Left / Black / 9
KEY_E5          = $08           ; E / 5 / Queen
KEY_F6          = $09           ; F / 6 / King
KEY_G7          = $0A           ; G / 7
KEY_A1          = $0B           ; A / 1 / Pawn
KEY_H8          = $0C           ; H / 8
KEY_B2          = $0D           ; B / 2 / Knight
KEY_C3          = $0E           ; C / 3 / Bishop
KEY_D4          = $0F           ; D / 4 / Rook
KEY_COUNT       = 16

KEY_RELEASED    = $80           ; key event bit 7: 1 = released, 0 = pressed

; --- Board fields and events (hal/board.s) --------------------------------
; field = 8 * rank_index + file_index, a1 = 0, h1 = 7, a8 = 56, h8 = 63

BRD_PLACED      = $80           ; board event bit 7: 1 = piece placed, 0 = lifted

; --- Cartridge identification (hal/cart.s) --------------------------------

CART_NONE       = 0             ; no cartridge (plausibility check failed)
CART_UNKNOWN    = 1             ; plausible content, unknown CRC
CART_HG440      = 2             ; HG 440 (MM IV), CRC-32 81ffcdfd
CART_HG550      = 3             ; HG 550 (MM V),  CRC-32 0359f13d

; --- Routines -------------------------------------------------------------

; hal/display.s
.global disp_init, disp_nmi
.global disp_clear, disp_raw, disp_set4, disp_hex8, disp_hex16, disp_dec
.global disp_str, disp_str_to, disp_fill, disp_lock, disp_unlock
.globalzp disp_buf, disp_phase

; hal/keys.s
.global key_init, key_nmi, key_get, key_down, key_flush
; hal/board.s
.global brd_init, brd_nmi, brd_nmi_leds, brd_get, brd_flush, brd_piece
.global brd_led_set, brd_led_clear, brd_led_blink, brd_led_alloff, brd_led_all
.global mled_set, mled_get
.global brd_state, brd_led, brd_blink
; hal/sound.s
.global snd_tone, snd_beep_ok, snd_beep_err, snd_click
; hal/timer.s
.global tmr_read, tmr_wait
; hal/crc.s
.global crc_init, crc_byte, crc_block, crc_final
.globalzp crc_val
; hal/cart.s
.global cart_check
; hal/nmi.s
.global hal_init, hal_nmi

.endif
