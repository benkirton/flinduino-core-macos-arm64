/*
 * Definitions Microchip's toolchain supplied and mainline GCC does not.
 *
 * cpp-startup.S calls the bootstrap hook indirectly:
 *
 *     la      t0,_on_bootstrap
 *     jalr    t0
 *
 * so it has to be real, callable code. Supplying it from a linker script as
 * PROVIDE(_on_bootstrap = 0) would link cleanly and then jump to address 0 on
 * every boot. In Microchip's build this symbol is weak and resolves to a real
 * function, so an empty weak stub matches that behaviour and still lets a
 * sketch or library override it by defining its own _on_bootstrap.
 *
 * The other two symbols this startup path wants, _ramfunc_begin and
 * _bmxdkpba_address, are absolute linker symbols rather than variables - the
 * startup code takes their address, not their contents - so they cannot be
 * defined here and live in flinduino-compat.ld instead.
 */

__attribute__((weak)) void _on_bootstrap(void)
{
}
