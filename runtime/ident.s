; SPDX-License-Identifier: MIT
; runtime/ident.s -- ROM identification block (layout: include/ident.inc).
;
; Version and timestamp come from build/version.inc, generated from the
; VERSION and RELEASE_DATE files by tools/mkversion.pl. The CRC field is patched after
; linking by tools/romtool.pl.

.include "ident.inc"
.include "version.inc"

.segment "IDENT"

ident:
  .assert ident = IDENT_BASE, lderror, "ident: block not at IDENT_BASE"
  .byte "MM-IV-DIAG"
  .res IDENT_MAGIC_LEN - (* - ident), $00
  .assert * - ident = IDENT_FORMAT, error, "ident: format offset"
  .byte IDENT_FORMAT_VERSION
  .assert * - ident = IDENT_VMAJOR, error, "ident: version offset"
  .byte VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH
  .assert * - ident = IDENT_VSTRING, error, "ident: version string offset"
  .byte VERSION_STRING
  .res IDENT_VSTRING - (* - ident) + IDENT_VSTRING_LEN, $00
  .assert * - ident = IDENT_CONTACT, error, "ident: contact offset"
  .byte "mm4@strcmp.org"         ; contact for bug reports
  .assert * - ident < IDENT_CONTACT + IDENT_CONTACT_LEN, error, "ident: contact too long"
  .res IDENT_CONTACT - (* - ident) + IDENT_CONTACT_LEN, $00
  .assert * - ident = IDENT_BUILD, error, "ident: build time offset"
  .byte BUILD_TIMESTAMP
  .res IDENT_BUILD - (* - ident) + IDENT_BUILD_LEN, $00
  .assert * - ident = IDENT_CRC, error, "ident: CRC offset"
  .dword $00000000              ; patched by tools/romtool.pl
  .assert * - ident = IDENT_BCRC, error, "ident: block CRC offset"
  .res IDENT_BCRC_LEN, $00       ; patched by tools/romtool.pl
  .res IDENT_SIZE - (* - ident), $FF
