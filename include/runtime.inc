; SPDX-License-Identifier: MIT
; include/runtime.inc -- runtime zero page, constants and API.
;
; Runtime zero page lives at fixed addresses $00-$17 (cfg/rom.cfg: ZP_RT).
; The addresses are fixed rather than linker-placed because the boot
; address-line test writes $00, $01, $02, $04, $08, $10 before the
; runtime variables are initialised; none of the variables it needs at
; that point (rt_mt_ptr) may sit on a power of two.

.ifndef RUNTIME_INC
RUNTIME_INC = 1

; --- Zero page (ZP_RT, $00-$17) --------------------------------------------

nmi_magic       = $00           ; 2 bytes: NMI_MAGIC0/1 = full NMI handler active
rt_ticks        = $02           ; 4 bytes: 600 Hz tick counter, little endian
rt_mt_ptr       = $06           ; 2 bytes: memory test pointer (low byte 0)
rt_mt_first     = $08           ; memory test: first page
rt_mt_last      = $09           ; memory test: last page (inclusive)
rt_mt_bg        = $0A           ; memory test: background pattern
rt_mt_bgc       = $0B           ; memory test: complement of background
rt_err_word     = $0C           ; 2 bytes: fatal error value (address, PC)
rt_err_data     = $0E           ; fatal error data byte (bits, read value)
rt_err_code     = $0F           ; fatal error code (RT_E_*)
rt_f_scr        = $10           ; 4 bytes: fatal display screen, index 0 = right
rt_f_phase      = $14           ; fatal loop: LCD common phase ($00/$FF)
rt_f_count      = $15           ; fatal loop: half periods left on screen
rt_f_beep       = $16           ; fatal loop: half periods left with tone
                                ; $17 reserved

; Values never written by the boot memory tests (backgrounds $00/$FF/
; $55/$AA, address-line test $10-$1D), so test patterns cannot activate
; the full NMI handler by accident.
NMI_MAGIC0      = $4D
NMI_MAGIC1      = $B2

; --- Fatal error codes (docs/codes.md) ------------------------------------

RT_E_RAM        = $01           ; RAM data error: word = address, data = failing bits
RT_E_ADDR       = $02           ; RAM address line error: word = address, data = value read
RT_E_ROM        = $03           ; ROM checksum error (diag)
RT_E_IRQ        = $04           ; unexpected IRQ: word = interrupted PC
RT_E_BRK        = $05           ; BRK executed: word = address of the BRK

; --- API --------------------------------------------------------------------

.global rt_march_u              ; runtime/memtest.s
.global rt_fatal                ; runtime/fatal.s
.global rt_hexfont              ; runtime/font.s: 16 x 7-segment hex digits
.global nmi, irq, reset

.endif
