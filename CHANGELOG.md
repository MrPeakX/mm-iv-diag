# Changelog

All notable changes to MM-IV-DIAG. Versions follow
[Semantic Versioning](https://semver.org/).

## [1.4.1] - 2026-11-19

First public release.

- Power-on: pre-RAM test of zero page and stack page, address-line test,
  RAM test (March U), ROM check (CRC-32 per 4 KiB block); `dIAG`, the
  version, then `PA55` or an error code.
- Menu with nine tests: display, sound, keys, LEDs, sensors, RAM and ROM
  loop, cartridge (HG 440 / HG 550 by CRC-32), info, and a combined
  board LED and sound test.
- Key `0` pauses and resumes a running test, so a faulty segment or LED
  can be watched while tapping on the unit. In the key test `CL` shows
  its code; hold it for 1 s to leave.
- Runtime and HAL (display with AC drive, keys, sound, sensor board and
  LEDs, timer, CRC-32, cartridge) separate from the diagnostic
  application, documented in docs/hal-api.md.
- Reproducible build: the timestamp in the ident block (shown by test 8)
  is the release date from `RELEASE_DATE`, not the time of the build.
  Building a release tag gives the published image bit for bit (compare
  with `sha256sum`).
