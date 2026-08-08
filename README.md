# flinduino-core-arm64

An Arduino board platform for the Flinders University **Flinduino**
(PIC32MX250F128D) that actually runs on Apple Silicon Macs.

The board package Flinders distribute contains a compiler built as a **32-bit
i386** Mach-O binary. macOS removed 32-bit support in Catalina (2019), so that
package has not compiled on *any* Mac — Intel or Apple Silicon — since then.
Rosetta cannot help: it translates x86_64, never i386.

This platform replaces the compiler with a native arm64 build of GCC 10.2 for
`mipsel-pic32-elf`, and the uploader with a native arm64 `pic32prog`. Nothing
here runs under Rosetta or emulation, and nothing needs a vendor account.

**Verified on hardware:** GPIO, the core timer (`delay`/`millis`), USB CDC
serial, and buttonless upload — parity with the original toolchain.

---

## Install (students)

No terminal, no Docker, no git. Requires an Apple Silicon Mac and the Arduino
IDE.

1. **Arduino IDE → Settings → Additional Boards Manager URLs**, add:

   ```
   https://raw.githubusercontent.com/benkirton/flinduino-core-arm64/main/package_flinduino_arm64_index.json
   ```

2. **Tools → Board → Boards Manager**, search `Flinduino`, install
   **Flinduino (arm64)**.

3. **Tools → Board → Flinduino (arm64) → Flinduino**, then **Tools → Port** and
   pick the `usbmodem` entry.

Upload as normal. The compiler and uploader are installed for you.

> If you also see a plain **Flinduino** board, the original Flinders package is
> still installed. Pick the **(arm64)** one — the original cannot compile on any
> Mac made since 2019.

### Uploading

Uploads are buttonless: the IDE opens the port at 1200 baud, which asks the
running sketch to reset into the bootloader.

That relies on the sketch currently on the board still having USB alive. If you
upload something that hangs before USB starts, **hold BOOT and tap RESET** while
uploading. The bootloader always survives — see [Safety](#safety).

---

## Install (from source)

Everything above is reproducible.

```bash
git clone https://github.com/benkirton/flinduino-core-arm64
cd flinduino-core-arm64

tools/setup-toolchain.sh    # toolchain + regenerated PIC32 support files
tools/build-pic32prog.sh    # native arm64 uploader
bin/flinduino doctor        # verify, and record local paths
```

Needs [`arduino-cli`](https://arduino.github.io/arduino-cli/)
(`brew install arduino-cli`), Docker (used *only* to run the support-file
generator, which is PHP — nothing is installed outside this directory), and
`brew install autoconf automake pkg-config` for the uploader.

`doctor` writes `pic32/platform.local.txt` with your machine's paths. Re-run it
if you move the checkout; it is the only step that records absolute paths.

To use it from the IDE without Boards Manager:

```bash
mkdir -p ~/Documents/Arduino/hardware/flinduino
ln -s "$PWD/pic32" ~/Documents/Arduino/hardware/flinduino/pic32
```

Restart the IDE. It will show as `Flinduino (arm64) (in Sketchbook)` — the
suffix is added by the IDE for anything installed this way.

### Prebuilt components

One thing is downloaded rather than built here:

| Component | Source | Why |
|---|---|---|
| `mipsel-pic32-elf` GCC 10.2.0 (arm64e) | [MajenkoProjects/chipkit-compiler](https://github.com/MajenkoProjects/chipkit-compiler/releases) | Building a cross-GCC from scratch is a long job. The crosstool-NG config used to produce it is published, so it is reproducible. |

Everything else is built or generated locally: the PIC32 headers and libraries
are regenerated from source by [`pic32-genfiles`](https://github.com/MajenkoProjects/pic32-genfiles)
with the patches in `patches/`, and `pic32prog` is compiled from
[Majenko's fork](https://github.com/majenkotech/pic32prog-autotools).

---

## Command line

```bash
bin/flinduino doctor                 # check the install, record local paths
bin/flinduino build   examples/Blink
bin/flinduino check   examples/Blink # verify flash layout, do not flash
bin/flinduino run     examples/Blink # build + check + flash
bin/flinduino flash   examples/Blink
bin/flinduino monitor
```

A sketch directory must share its name with the `.ino` inside it. Output goes to
`<sketch>/build/`.

> **Close the IDE's Serial Monitor before uploading from the terminal.** It holds
> the port open and the uploader will wait on `Resource busy`. The IDE manages
> this itself when uploading from inside the IDE.

---

## Safety

The Flinduino boots from a bootloader in boot flash, which also owns the DEVCFG
configuration words. An image that writes there needs a PICkit 3 to recover.

`bin/flinduino check` runs before every flash and refuses the upload unless:

- the entry point is `0x9d001000`, the bootloader's application entry
- `.image_ptr_table` sits at `0x9d0000f8`
- **nothing** is allocated in boot flash (`0x9fc00000`) or DEVCFG (`0xbfc02ff0`)

If an upload does leave the board unresponsive, the bootloader still works:
hold BOOT, tap RESET, and upload something known-good. A forced bootloader stays
active rather than timing out, so there is no rush.

Uploading from the IDE does not run this check. Prefer the command line for
anything experimental.

---

## Layout

```
pic32/                        the Arduino platform (boards.txt, platform.txt, cores, variants, libraries)
bin/flinduino                 build / check / flash / monitor / doctor
tools/setup-toolchain.sh      assembles the toolchain, idempotent
tools/build-pic32prog.sh      builds the native arm64 uploader
tools/make-release.sh         builds the Boards Manager archives and index
patches/pic32-genfiles/       fixes for the support-file generator
patches/toolchain/            sys/attribs.h shim
examples/Blink/               known-good test sketch
docs/PORTING.md               every bug found, why it happened, and what not to "fix"
package_flinduino_arm64_index.json   the Boards Manager index
```

Not in version control: `toolchain/`, `prebuilt/`, `release/` — all regenerated
by the scripts above.

---

## Releasing

```bash
tools/make-release.sh https://github.com/benkirton/flinduino-core-arm64/releases/download/v1.0.0 1.0.0
```

Builds two tool archives and a platform archive into `release/`, and writes
`package_flinduino_arm64_index.json` at the repo root with sizes and SHA-256
checksums. Upload the three archives to that GitHub release, commit the index,
and the raw URL of the index is what students paste.

---

## Known limitations

- **Only PIC32MX250F128D is verified.** The generator fixes are general, but the
  PPS base address in `pinmap/mx/mx1xx2xx` is correct for MX1xx/2xx only. Other
  families need their own base.
- **`-G0` instead of `-G1024`.** Small-data addressing cannot reach the
  linker-defined absolute symbols the core uses, so it is disabled. Costs a
  little code size and speed.
- **Larger binaries.** Blink is ~40 KB against ~27 KB from the original
  toolchain — GCC 10 plus `-G0`. Comfortable inside the 120 KB available.
- **Untested subsystems.** ADC, PWM/`tone`, SPI, I2C and the bundled libraries
  compile but have not been exercised on hardware. Their registers were among
  those corrected (see [docs/PORTING.md](docs/PORTING.md)), so they are more
  likely correct than before — but treat them as unproven.
- **macOS arm64 only.** Nothing here helps Intel Macs, Windows or Linux, all of
  which already have a working toolchain.

---

## Upstream bugs found

Four are worth reporting to their projects; see
[docs/PORTING.md](docs/PORTING.md) for the analysis.

- **pic32-genfiles** emits every register's bitfield struct in reverse bit
  order, on every peripheral.
- **pic32-genfiles** never applies a peripheral base to the PPS registers, and
  parses their offsets as octal.
- **pic32-genfiles** writes the ADC offsets in decimal and has a `${reg}` typo
  for `${rpn}` in the timer definition.
- **Majenko's `mips-chipKIT-application-COMMON.ld`** never collects `*(.bss)`,
  so with `-fdata-sections` every bss section orphans into loadable flash and is
  never zeroed.

---

## Licensing

`LICENSE` is Apache 2.0, matching
[Flinduino/flinduino-core](https://github.com/Flinduino/flinduino-core), which
this derives from.

Individual files under `pic32/cores/` and `pic32/variants/` carry their own
headers — chipKIT and Arduino sources are LGPL 2.1, and some files are
Microchip's under BSD-style terms. Those headers govern those files. If you are
redistributing this, read them rather than assuming the root licence covers
everything.

---

## Credits

- [Majenko](https://github.com/MajenkoProjects) — the `mipsel-pic32-elf`
  toolchain, `pic32-genfiles`, the ported linker script, and `pic32prog`.
  This port is mostly a matter of finding where those and the chipKIT core
  disagree.
- [chipKIT](https://github.com/chipKIT32) — the PIC32 Arduino core.
- Flinders University — the Flinduino board and its variant definitions.
