# Contributing

Issues and pull requests are welcome.

## Reporting a problem

Please include the output of:

```bash
bin/flinduino doctor
```

or, if you installed via Boards Manager:

```bash
arduino-cli core list
arduino-cli version
sw_vers
```

Say which board you selected (`Flinduino` or `Flinduino Baseboard`) and whether
the LED blinks — that one fact separates "the core never started" from "the core
runs and one subsystem is broken", which is most of the diagnosis.

## Getting set up

```bash
tools/setup-toolchain.sh    # toolchain + regenerated PIC32 support files
tools/build-pic32prog.sh    # native arm64 uploader
bin/flinduino doctor
bin/flinduino run examples/Blink
```

`examples/Blink` is the known-good reference. If it blinks the LED, enumerates
as USB CDC and prints over serial, the whole chain works.

## Before changing anything

Read [docs/PORTING.md](docs/PORTING.md). It records not just what was fixed but
several things that *look* like bugs and are not, and changes that seem correct
and break the build. In particular:

- **Do not add `-I{sysroot}/include`.** The toolchain already knows its target
  include directory; forcing it breaks the `#include_next` chain the C++ headers
  rely on.
- **Do not define `__XC32_VERSION`.** It selects a startup path needing a
  `.dinit` table only Microchip's linker generates.
- **Do not fold `.sdata`/`.sbss` into `.data`/`.bss`.** They are gp-addressed;
  moving them overflows `R_MIPS_GPREL16`.
- **`-msoft-float` and `-DCPP_INIT` are load-bearing.** Removing either produces
  a build that links and then misbehaves at runtime.

## Verifying a change

Two checks catch most regressions.

**Addresses and layout**, statically:

```bash
bin/flinduino check examples/Blink        # entry point, image table, boot flash
mipsel-pic32-elf-nm <elf> | awk '$2=="A"{print $3,$1}'   # SFR addresses
```

If you have a copy of Microchip's `p32mx250f128d.h`, diffing our SFR addresses
and bitfield positions against it is how the original bugs were found. Reading
code and reasoning about it produced several wrong answers; mechanical diffing
did not.

**Behaviour**, on hardware: the LED (RB15 on the base variant), USB enumeration,
and serial output. If a build flashes but does nothing, bisect with staged LED
markers rather than guessing — blink a distinct count at successive points in
startup, flash once, and read off how far it got. Keep flashes around 300 ms;
faster than that and they cannot be counted reliably.

## Safety

The bootloader lives in boot flash and owns DEVCFG. `bin/flinduino check` runs
before every upload and refuses anything that would write there. Prefer
`bin/flinduino run` over `arduino-cli upload` while developing — the latter does
not run that check.

If an upload does leave the board unresponsive, the bootloader survives: hold
BOOT, tap RESET, and flash something known-good. A forced bootloader stays
active rather than timing out.

## Upstream fixes

Several fixes here belong in other projects rather than this one. If you are
improving them, please send them upstream too:

- The generator fixes in `patches/pic32-genfiles/` →
  [MajenkoProjects/pic32-genfiles](https://github.com/MajenkoProjects/pic32-genfiles)
- The `.bss` linker script fix (applied by `tools/setup-toolchain.sh`) →
  [MajenkoProjects/chipkit-compiler](https://github.com/MajenkoProjects/chipkit-compiler)

## Releasing

```bash
tools/make-release.sh <base-url> <version>
```

Upload the three archives it produces to that release, then commit the
regenerated index. **Upload the archives from the same run that generated the
index** — `tar` is not byte-deterministic, so rebuilding invalidates the
checksums and Board Manager will reject the install with a confusing
"archive hash differs" error.

`raw.githubusercontent.com` caches the index for a few minutes, so a fresh
install straight after a push may still fetch the previous one. Verify with
`curl` before concluding something is broken.
