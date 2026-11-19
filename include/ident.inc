; SPDX-License-Identifier: MIT
; include/ident.inc -- ROM identification block layout.
;
; The block sits at a fixed address at the start of the ROM. Offsets are
; relative to IDENT_BASE. tools/romtool.pl reads the IDENT_* values from
; this file, so this is the only place that defines the layout.

.ifndef IDENT_INC
IDENT_INC = 1

IDENT_BASE      = $8000         ; fixed address, first byte of the ROM
IDENT_SIZE      = $80           ; whole block, unused bytes are $FF

IDENT_MAGIC     = $00           ; 16 bytes: "MM-IV-DIAG", NUL padded
IDENT_MAGIC_LEN = $10
IDENT_FORMAT    = $10           ; 1 byte: layout version of this block
IDENT_VMAJOR    = $11           ; 1 byte: version major (binary)
IDENT_VMINOR    = $12           ; 1 byte: version minor (binary)
IDENT_VPATCH    = $13           ; 1 byte: version patch (binary)
IDENT_VSTRING   = $14           ; 12 bytes: version string, NUL padded
IDENT_VSTRING_LEN = $0C
IDENT_CONTACT   = $20           ; 16 bytes: contact e-mail address, NUL padded
                                ; (at least one NUL)
IDENT_CONTACT_LEN = $10
IDENT_BUILD     = $30           ; 20 bytes: RELEASE_DATE "YYYY-MM-DD HH:MM:SS" UTC, NUL
IDENT_BUILD_LEN = $14
IDENT_CRC       = $44           ; 4 bytes: CRC-32 (little endian) of the whole
                                ; image, CRC area taken as zero
IDENT_CRC_LEN   = $04
IDENT_BCRC      = $48           ; 8 x 4 bytes: CRC-32 of each 4 KiB block
                                ; $8000 + n * $1000, CRC area taken as zero
IDENT_BCRC_LEN  = $20
IDENT_BLOCKS    = 8
IDENT_BLOCK_SIZE = $1000

; CRC area: the bytes holding the CRCs (IDENT_CRC .. end of IDENT_BCRC).
; Every CRC above is computed with these bytes replaced by zero.
IDENT_CRC_AREA  = IDENT_CRC
IDENT_CRC_AREA_LEN = IDENT_CRC_LEN + IDENT_BCRC_LEN

IDENT_FORMAT_VERSION = 3

.endif
