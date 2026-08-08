/*
 * Supplementary linker script, applied after the per-chip and COMMON scripts.
 *
 * Majenko's mips-chipKIT-application-COMMON.ld has its entire .ramfunc output
 * section commented out, so the symbols cpp-startup.S expects for the RAM
 * function relocation are never defined and the link fails.
 *
 * Nothing in this core places code in .ramfunc, so zero is correct rather than
 * merely convenient: cpp-startup.S does
 *
 *     la      t1,_ramfunc_length
 *     beqz    t1,_ramfunc_done
 *
 * and _ramfunc_done sits past both the copy loop and the BMXDKPBA programming,
 * so with a zero length the whole block is skipped and none of these addresses
 * is ever dereferenced. BMXDKPBA is left at its reset value of 0, which maps
 * all of data RAM as data - exactly what is wanted with no RAM functions.
 *
 * PROVIDE, not assignment, so these defer automatically if that section in
 * COMMON.ld is ever uncommented.
 */

PROVIDE(_ramfunc_begin       = 0);
PROVIDE(_ramfunc_end         = 0);
PROVIDE(_ramfunc_length      = 0);
PROVIDE(_ramfunc_image_begin = 0);
PROVIDE(_bmxdkpba_address    = 0);
