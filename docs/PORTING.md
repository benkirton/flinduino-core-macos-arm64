# Porting the Flinduino core to a mainline PIC32 toolchain

What was broken, why, and what was changed. Written so the next person can
verify the reasoning rather than trust it.

## The starting problem

Flinders ship a chipKIT-derived board package whose compiler binaries are
**32-bit i386** Mach-O. macOS removed 32-bit support in Catalina, so the package
has been broken on every Mac since 2019. Rosetta translates x86_64 only.

Nobody had fixed it upstream: `chipKIT-cxx` issue #16, *"Rebuild for 64-bit
hosts (requirement for macOS Catalina)"*, has been open since March 2020 with
zero comments. PlatformIO's `toolchain-microchippic32` advertises `darwin_arm64`
in its metadata, but the package contains the same i386 binaries.

What did exist was [Majenko's `mipsel-pic32-elf`](https://github.com/MajenkoProjects/chipkit-compiler)
— mainline GCC 10.2, with a native `arm64e-apple-darwin20` release — plus
[`pic32-genfiles`](https://github.com/MajenkoProjects/pic32-genfiles) to
generate the per-chip headers and libraries. That is the foundation used here.

## The shape of the problem

Almost every bug fell into one class:

> **pic32-genfiles and Microchip disagree about a macro, symbol or layout, and
> the chipKIT core reads it with Microchip's meaning.**

These fail *silently*. Nothing errors; code compiles and links and then does
the wrong thing, or vanishes entirely. Four of the seven bugs below are this.

The reliable technique was **mechanical diffing against Microchip's header for
this exact part** — not reading code and reasoning. That found 75 wrong
addresses and 192 wrong bitfield positions in two passes. Reasoning from headers
produced three wrong theories that had to be retracted.

On the hardware side, the equivalent was **staged LED markers**: blink a
distinct count at successive points in startup, flash once, and read off how far
it got. That located a hang in `pinMode` that no amount of static analysis had.

---

## Fixes in pic32-genfiles

All four are in
`patches/pic32-genfiles/0001-fix-generated-sfr-addresses-and-bitfield-order.patch`
and are worth sending upstream. Together they made a 325-line downstream
workaround unnecessary.

### 1. Bitfield structs were emitted in reverse bit order

`collapse()` in `bin/pic32-genfiles` walks bits high to low:

```php
for ($i = 31; $i >= 0; $i--) {
```

GCC allocates bitfields LSB-first on a little-endian target, so **every**
register's `Xbits` struct on **every** peripheral came out mirrored — each field
landing at `31 - correct_bit`.

The loop cannot simply be flipped: `pos` is what makes the `_X_Y_POSITION` and
`_MASK` macros correct, and those were already right. The fix reverses only at
struct emission.

That genfiles' own POSITION macros agreed with Microchip is what proves the
structs were the bug — the header contradicted itself.

*Why it took so long to find:* the core uses whole-register writes
(`TRISBCLR = mask`) for GPIO and timers, so those worked. USB was the first
subsystem to depend on named bits.

Verified: 192 fields across 14 registers, 0 mismatched after the fix.

### 2. PPS registers had no peripheral base

`peripherals/mx/pps_func` and `pps_pin` both reference `${PPS_BASE}`, which is
**never defined anywhere**, so every PPS register came out as a bare offset.
`SET PPS_BASE` does not help — settings do not propagate into included files —
so it is passed per include.

### 3. PPS offsets were parsed as octal

The same pinmap writes offsets with leading zeros:

```
INCLUDE peripherals/mx/pps_pin OFFSET=0100 PIN=A0
```

PHP's `intval($x, 0)` reads a leading `0` as octal, so `0100` became 64
(`0x40`) instead of `0x100`. Worse, `001C` is not valid octal and truncated to
`1`. Now written `0x0100`.

Together with fix 2: `RPA0R = 0xBF80FA00 + 0x0100 = 0xBF80FB00`, matching
Microchip exactly.

**This was the bug that hung `pinMode`.** `pins_arduino.h` uses `RPA0R` as
`_RPOBASE`, the PPS output block base. With it at `0x40`, `pinMode` stored to
address `0x40`, took a bus error, and never returned.

### 4. ADC offsets decimal, timer offset never evaluated

```
REG ${rpn ${BASE} 10 +} AD1CON2      # decimal 10, should be 0x10
REG ${reg ${BASE} 0x10 +} TMR${INDEX} # "reg" is not a command; should be "rpn"
```

The ADC typo put `AD1CON2` at `base+10` = `0xBF80900A` instead of `0xBF809010`.
The timer typo left `TMR2`–`TMR5` unevaluated.

**Result of 1–4:** 821 SFR addresses compared against Microchip's header, **0
mismatched**, with no downstream patching at all.

---

## Fixes in Majenko's linker script

### 5. `.bss` was never collected

`mips-chipKIT-application-COMMON.ld` defines its `.bss` output section as:

```
.bss : { *(.dynbss) *(.gnu.linkonce.b.*) *(COMMON) }
```

There is no `*(.bss)`. With `-fdata-sections`, every bss chunk — `.bss.Serial`,
`.bss.usbDriver`, 17 in total — orphaned into **loadable flash** instead of
becoming NOBITS in RAM, and sat outside `_bss_begin.._bss_end` so the startup
zero loop never touched them.

Applied by `tools/setup-toolchain.sh` rather than as a patch file, because the
upstream file has CRLF line endings.

**Do not also fold `.sdata`/`.sbss` into `.data`/`.bss`.** They are gp-addressed,
newlib and libgcc are built with small-data enabled, and moving them overflows
`R_MIPS_GPREL16`. Their orphan placement lands them near `_gp` and works.

Its `.ramfunc` block is also entirely commented out, which is why
`flinduino-compat.ld` has to provide `_ramfunc_*` and `_bmxdkpba_address`.

---

## Fixes in the platform and core

### 6. `__PIC32MX__` — the silent one

Microchip's `-mprocessor=` **predefined** the family macro. Mainline GCC does
not, so `USB_FS.cpp` compiled to a **24-byte object with zero symbols** — no
error, no warning. It surfaced only as undefined vtable references at link.

Fixed by adding `-D__PIC32MX__` to the compiler flags.

### 7. C++ constructors never ran

`cpp-startup.S` guards the call to `_init` behind `CPP_INIT`, which is only
defined when `__XC32_VERSION > 1000`. Mainline GCC does not define that, so
`.ctors` held registered constructors that nothing ever walked — `Serial`, the
USB objects, every global, never constructed.

Two things were needed:

- `-DCPP_INIT` so the startup calls `_init`
- `crti.o` and `crtn.o` on the link line — `-nostartfiles` drops them, so
  `_init` did not exist at all. `crtbegin.o`/`crtend.o` are already linked
  implicitly; adding those too gives a duplicate `__TMC_END__`.

**Do not define `__XC32_VERSION` to fix this.** It also selects the modern
startup path, which needs a `.dinit` data-init table that only Microchip's
linker generates. The old path (`USE_OLD_INIT`) is the GNU-compatible one and is
what Majenko's linker script is written for.

### Smaller items

| Issue | Fix |
|---|---|
| `sys/attribs.h` absent | shim in `patches/toolchain/`. Does **not** define `__section__` — that is a GCC-reserved spelling and newlib uses it, so defining it breaks every TU reaching `<sys/reent.h>` |
| `_bcc0`/`_bsc0`/`_bcsc0` are XC32 builtins | implemented with MIPS inline asm in `p32xxxx.h` |
| No USB interrupt macros in genfiles | `_USB_1_VECTOR 30`, `_USB_IRQ 35` in `p32xxxx.h`, guarded |
| `abs()` macro vs `<cstdlib>` | `wiring.h` pulls the standard headers in *before* the macro; `_SKIP_STDLIB_ABS` is a Microchip-only newlib hook |
| `.section X,code,keep` | Microchip GAS syntax → `,"ax",@progbits` (9 sites) |
| `addiu LEN,$0,0xFFFFFFFC` | `addiu` takes a signed 16-bit immediate → `-4` |
| 23 duplicate symbols | weakened in `lib32*.a` so newlib/libstdc++ win, rather than `--allow-multiple-definition` which would hide real clashes |
| `-G1024` | → `-G0`; small-data cannot reach linker-defined absolute symbols |
| `-Map="..."`, `-L"..."` | unquoted; the quotes reached ld as part of the filename |
| `objcopy --change-addresses -0x80000000` | → `+0x80000000`; ELF addresses are sign-extended to 64-bit, so adding wraps the high word correctly |
| 7 macros defined by both genfiles and `cpudefs_table.h` | `#undef`ed at the end of `p32xxxx.h`, handing ownership to `cpudefs_table.h`. Values agree where used (`_CPU_NAME_`, `__PIC32_PINS__ 44`, `__NUM_DMA_CHANNELS__ 4`); the rest are presence flags tested only with `defined()`. Cosmetic, but it was a warning per macro per translation unit |

### Remaining known warning

One warning survives, from chipKIT's own `main.cpp`:

```
Warning: setting incorrect section attributes for .comment
```

It comes from

```c
__attribute__((section(".comment"))) void (*__use_force_isr_install)(void) = &__use_isr_install;
```

a deliberate trick to force the ISR install code to be linked by referencing it
from a non-alloc section. GAS objects to a data pointer landing in `.comment`.
It is harmless — interrupts demonstrably work — and changing the section risks
defeating the force-link, so it is left alone.

---

## The uploader

The `pic32prog` in the Flinders package is an i386+x86_64 fat binary, so it needs
Rosetta. `tools/build-pic32prog.sh` builds it natively for arm64 instead, which
makes the whole toolchain Rosetta-free.

Build **Majenko's fork**, not upstream `sergev/pic32prog`. Upstream 2.0.1 has no
`-R` flag, and both `platform.txt` and `bin/flinduino` depend on it to wait for
the board to re-enumerate after a 1200-baud touch. A build without it fails
silently in the worst way: it works when the board is already in the bootloader
and does not when it is not.

Two build notes: `autoreconf -if` is required, not `-i` (the tree ships
pre-generated autotools files older than current autoconf, and `autopoint`
refuses to overwrite them without `--force`); and arm64 binaries must be signed
to run at all, so the script ad-hoc signs the result. The build links only
system frameworks, so nothing needs bundling.

## Traps worth knowing

**A stale arduino-cli sketch cache wedges the build.** After changing anything in
the platform, `arduino-cli` spins at 100% CPU with no subprocesses and no output,
forever. It is not a compiler problem. `bin/flinduino` always passes `--clean`.

**A forced bootloader does not time out.** Entering it with the BOOT button keeps
it there, and it enumerates as a CDC port. A board sitting there is *not*
evidence that the application runs — only a plain RESET tests that. This
produced one wrong "it works!" conclusion during the port.

**`-I{sysroot}/include` looks correct and is harmful.** The toolchain already
knows its target include directory. Forcing it onto `-I` puts the C headers
ahead of where GCC expects and breaks the `#include_next` chain the C++ headers
rely on. Symptom: `'abs' has not been declared in '::'`.

---

## Verifying a change

```bash
# addresses, against Microchip's header for this part
mipsel-pic32-elf-nm <elf> | awk '$2=="A"{print $3,$1}'

# layout, against the bootloader's expectations
bin/flinduino check <sketch>
```

The behavioural oracle is the original toolchain. A correct build blinks
`LED_BUILTIN` (RB15), enumerates as USB CDC, and prints over serial. If a change
breaks one of those, the staged-marker technique in the git history narrows it
to a single statement in one flash.
