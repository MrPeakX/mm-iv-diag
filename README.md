# MM-IV-DIAG

A standalone diagnostic ROM for the Hegener + Glaser Mephisto MM IV and
MM V chess modules. It tests the module (RAM, ROM, opening book
cartridge slot), the 7-segment LCD display unit and the sensor board,
and runs without any original ROM.

Version 1.4.1.

## Supported hardware

- Modules: Mephisto MM IV and MM V (identical hardware, 65C02 at
  4.9152 MHz). The ROM uses only the common 65C02 subset, so it runs on
  both CPU variants found in these modules (Rockwell R65C02, GTE
  G65SC02).
- Boards: Mephisto Modular, Exclusive and München (same interface).
- Display: the 7-segment LCD display unit of the modular series. The
  later dot-matrix display is not supported.
- Opening book cartridges HG 440 (MM IV) and HG 550 (MM V) are
  recognised in test 7.

## Requirements

- [cc65](https://cc65.github.io/) (ca65, ld65, ar65), tested with 2.19
- GNU make
- Perl v5.40 or later (core modules only)

## Build

```
make            # build/mm-iv-diag-1.4.1.bin
make clean      # remove build/
```

The image is exactly 32768 bytes for `$8000-$FFFF`, unused space `$FF`.
`make` also checks that the code uses no instructions missing on the
G65SC02 (no Rockwell bit instructions, no WAI/STP) and verifies size,
ident block and checksums of the image.

The build is reproducible: the timestamp in the ident block is the
release date from `RELEASE_DATE`, not the time of the build. Building a
release tag gives the published image bit for bit; compare its SHA-256
with the checksum published with the release:

```
sha256sum build/mm-iv-diag-1.4.1.bin
```

`SOURCE_DATE_EPOCH` overrides the timestamp explicitly (the image then
differs from the release).

## Using the image

Program `build/mm-iv-diag-<version>.bin` into one of:

- a 27C256 EPROM (32 KiB),
- an SST27SF256 or another 27C256-compatible flash or EEPROM,
- a ROM emulator in the module's ROM socket,

and fit it instead of the module ROM. Keep the original ROM safe; it
goes back in afterwards. Programming the chip needs an external
programmer and is not part of this project.

Power-on (details: [docs/codes.md](docs/codes.md)):

1. `dIAG` while RAM and ROM are tested (under 1 s).
2. The version, then `PA55` with a short beep. RAM errors stop here with
   an error code; a ROM error shows `E-03` and the unit stays usable.
3. The menu: `dIAG` and the version alternate every 5 s with a wipe
   through all segments. The unit always shows a sign of life; a frozen
   display means the program has stopped.

Reset: press both RES buttons together.

## Menu

Press `1`-`8` (keys A/1 ... H/8) to start a test, `9` (Left / 9) for the
combined board LED and sound test, `CL` to return to the menu. `0`
(Right / 0) pauses a running test and resumes it, so a faulty segment
or LED can be watched while tapping on the unit. In the key test `0`
and `CL` show their codes; hold `CL` for 1 s to leave.

| Key | Test |
|-----|------|
| 1 | display: all segments, each digit, each segment line |
| 2 | sound: C major scale, frequency on the display |
| 3 | keys: each key shows its code `c-hh` |
| 4 | LEDs: running light over the 64 fields, the 6 module LEDs, all on |
| 5 | sensors: a piece lights its field; changes shown as `P-E4` / `L-E4` |
| 6 | RAM and ROM loop with pass counter and error counts |
| 7 | cartridge: HG 440 / HG 550 / unknown / none, CRC-32 |
| 8 | info: version, build date (UTC), ROM CRC-32 |
| 9 | board LEDs and sound: a winking smiley, countdown 9 ... 0 on the board LEDs, then "Ode to Joy" |

All display codes and beep patterns: [docs/codes.md](docs/codes.md).

## Source layout

Runtime and hardware abstraction layer (HAL) are separate from the
diagnostic application, so the code can serve as a base for other
programs on the MM IV / MM V, such as a chess engine.

- `runtime/`: reset, pre-RAM test, NMI and IRQ handlers, vectors, ident block
- `hal/`: display, keys, sound, board, timer, cartridge, CRC-32
- `diag/`: the diagnostic application
- `include/`: hardware constants, HAL API, zero-page map, timing constants
- `cfg/`: ld65 linker configuration
- `tools/`: Perl build tools (version include, checksum patching and image check)

All tuning constants (debounce, tones, blink rates, LCD inversion) are
in `include/timing.inc`.

## Documentation

- [docs/hardware.md](docs/hardware.md): hardware, memory map, I/O protocols, NMI timing
- [docs/hal-api.md](docs/hal-api.md): HAL API, calling convention, zero-page map, NMI budget
- [docs/boot.md](docs/boot.md): power-on sequence, pre-RAM test
- [docs/codes.md](docs/codes.md): display codes and beep patterns
- [CHANGELOG.md](CHANGELOG.md)

## License

MIT, see [LICENSE](LICENSE).
