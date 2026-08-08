/*
 * Replacement for Microchip's <sys/attribs.h>.
 *
 * The chipKIT core and some libraries include this for ISR and ramfunc
 * attribute macros. Microchip's version leans on compiler extensions that only
 * exist in their patched GCC:
 *
 *   vector(n)       places a dispatch stub in .vector_n
 *   interrupt(ipl)  takes a named priority level, e.g. IPL3SOFT
 *   ramfunc         relocates a function into RAM
 *
 * Mainline GCC 10 has none of those. What it does have is `interrupt` (no
 * argument), `nomips16`, and `section`, which together get close enough:
 * putting the handler itself in .vector_n reproduces the placement, and
 * mips-chipKIT-application-COMMON.ld already ASSERTs that anything landing
 * there fits the 0x20-byte slot. So an over-large handler fails at link time
 * with "function at exception vector N too large" rather than silently
 * corrupting the next vector.
 *
 * The ipl argument is accepted and ignored. Mainline GCC cannot encode it, so
 * the handler does not set IPL on entry. The core already programs priorities
 * explicitly via the IPCxSET registers, which is what actually takes effect.
 * A handler that relied on the attribute alone to set its priority would run at
 * whatever IPL the hardware was left at.
 */
#ifndef __ATTRIBS_H
#define __ATTRIBS_H

#define __PIC32_STR1(x) #x
#define __PIC32_STR(x)  __PIC32_STR1(x)

/* Handler placed directly at its exception vector. */
#define __ISR(v, ...) \
    __attribute__((interrupt, nomips16, section(".vector_" __PIC32_STR(v))))

#define __ISR_AT_VECTOR(v, ...) \
    __attribute__((interrupt, nomips16, section(".vector_" __PIC32_STR(v))))

/* Single-vector mode: everything funnels through the general exception entry. */
#define __ISR_SINGLE()              __attribute__((interrupt, nomips16))
#define __ISR_SINGLE__              __attribute__((interrupt, nomips16))
#define __ISR_SINGLE_AT_VECTOR(v, ...) \
    __attribute__((interrupt, nomips16, section(".vector_" __PIC32_STR(v))))
#define __ISR_SINGLE_AT_VECTOR__(v, ...) \
    __attribute__((interrupt, nomips16, section(".vector_" __PIC32_STR(v))))

/*
 * Deliberately NOT defining __section__ or __unique_section__, which Microchip's
 * version does. Those are GCC's reserved double-underscore spellings, and newlib
 * uses them directly:
 *
 *   #define __ATTRIBUTE_IMPURE_PTR__ __attribute__((__section__(".data")))
 *
 * Defining __section__ as a function-like macro rewrites that into nested
 * __attribute__((__attribute__((...)))) and every translation unit that reaches
 * <sys/reent.h> fails to parse. Use __attribute__((section(...))) directly.
 */
#define __longcall__        __attribute__((long_call))

/*
 * No `ramfunc` attribute in mainline GCC. Section placement alone gets the code
 * into .ramfunc; the linker script is responsible for copying it to RAM. On a
 * PIC32MX this is only a speed optimisation, never a correctness requirement.
 */
#define __ramfunc__ \
    __attribute__((section(".ramfunc"), noinline))
#define __longramfunc__ \
    __attribute__((section(".ramfunc"), long_call, noinline))

#endif /* __ATTRIBS_H */
