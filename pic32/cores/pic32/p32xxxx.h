/*
 * Compatibility shim for building the chipKIT core with a mainline
 * mipsel-pic32-elf toolchain.
 *
 * The core includes <p32xxxx.h>, which came from Microchip's toolchain. The
 * mipsel-pic32-elf toolchain follows Microchip's newer convention instead,
 * where <xc.h> dispatches on the __<CHIP>__ define to the right proc header.
 * This forwards to it, so the core compiles unmodified.
 *
 * Everything below fills a gap in pic32-genfiles' generated headers. The
 * incorrect SFR addresses and bitfield layouts that used to be patched here
 * are now fixed in genfiles itself - see PORTING.md - so only these remain.
 */
#ifndef _P32XXXX_H
#define _P32XXXX_H

#include <xc.h>
#include <cp0defs.h>

/*
 * genfiles builds its interrupt tables from peripherals/mx12/interrupts, which
 * has no USB entry: it emits 43 _*_VECTOR and 63 _*_IRQ macros for this part
 * and none of them are USB, even though the chip has a USB peripheral and
 * genfiles itself sets __HAS_USB__. USB_FS.cpp needs both.
 *
 * Values are Microchip's, from their p32mx250f128d.h for this exact part.
 * Guarded, so they disappear if genfiles ever grows real definitions.
 */
#if defined(__HAS_USB__) && !defined(_USB_1_VECTOR)
#define _USB_1_VECTOR 30
#endif
#if defined(__HAS_USB__) && !defined(_USB_IRQ)
#define _USB_IRQ 35
#endif

/*
 * cp0defs.h defines its CP0 bit-set and bit-clear macros in terms of _bcc0,
 * _bsc0 and _bcsc0 but never defines those - under XC32 they are compiler
 * builtins. Mainline GCC has no such builtins, so genfiles ships the header
 * with the calls and nothing behind them, and the _CP0_BIC_DEBUG call in
 * wiring.c fails to link.
 *
 * Read-modify-write on a CP0 register, returning the previous value. The ehb
 * clears the execution hazard so the write has taken effect before any
 * dependent instruction runs.
 */
#ifndef _bcc0
#define _bcc0(reg, sel, clr) __extension__({                        \
    unsigned int __old, __new;                                      \
    __asm__ __volatile__ ("mfc0 %0, $%1, %2"                        \
                          : "=d" (__old) : "i" (reg), "i" (sel));   \
    __new = __old & ~((unsigned int)(clr));                         \
    __asm__ __volatile__ ("mtc0 %0, $%1, %2; ehb"                   \
                          : : "d" (__new), "i" (reg), "i" (sel));   \
    __old;                                                          \
})
#endif

#ifndef _bsc0
#define _bsc0(reg, sel, set) __extension__({                        \
    unsigned int __old, __new;                                      \
    __asm__ __volatile__ ("mfc0 %0, $%1, %2"                        \
                          : "=d" (__old) : "i" (reg), "i" (sel));   \
    __new = __old | ((unsigned int)(set));                          \
    __asm__ __volatile__ ("mtc0 %0, $%1, %2; ehb"                   \
                          : : "d" (__new), "i" (reg), "i" (sel));   \
    __old;                                                          \
})
#endif

#ifndef _bcsc0
#define _bcsc0(reg, sel, clr, set) __extension__({                    \
    unsigned int __old, __new;                                        \
    __asm__ __volatile__ ("mfc0 %0, $%1, %2"                          \
                          : "=d" (__old) : "i" (reg), "i" (sel));     \
    __new = (__old & ~((unsigned int)(clr))) | ((unsigned int)(set)); \
    __asm__ __volatile__ ("mtc0 %0, $%1, %2; ehb"                     \
                          : : "d" (__new), "i" (reg), "i" (sel));     \
    __old;                                                            \
})
#endif

/*
 * genfiles and chipKIT's cpudefs_table.h both describe the part, and seven
 * macros overlap. cpudefs_table.h is included later (wiring.h pulls p32_defs.h
 * after this header) so its definitions win regardless - the only effect is a
 * "redefined" warning per macro on every translation unit.
 *
 * The two sides agree where the value is used: _CPU_NAME_ is the same string,
 * __PIC32_PINS__ is 44 on both, __NUM_DMA_CHANNELS__ is 4 on both. The rest are
 * presence flags that genfiles gives the value 1 and chipKIT leaves empty, and
 * the core only ever tests them with defined().
 *
 * Undefining them here hands ownership to cpudefs_table.h, which is the file
 * the core actually consults, and drops the warnings. This must stay after the
 * __HAS_USB__ test above, which needs genfiles' definition still in scope.
 */
#undef _CPU_NAME_
#undef __HAS_DMA__
#undef __HAS_USB__
#undef __NUM_DMA_CHANNELS__
#undef __PIC32MX2XX__
#undef __PIC32_PINS__
#undef __PIC32_PPS__

#endif /* _P32XXXX_H */
