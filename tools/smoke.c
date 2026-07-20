/* smoke.c - end-to-end smoke test: host-edited source, NFS-shared,
 * compiled and run natively on OPENSTEP.
 *
 *   gcds next 'cd /ndrv/tools && cc -o /tmp/smoke smoke.c && /tmp/smoke'
 *
 * Strict C89 (NeXT cc 2.7.2.1).
 */
#include <stdio.h>

int main(void)
{
    long x;
    x = 40L + 2L;
    printf("smoke OK: %ld (compiled on OPENSTEP, source via gnfsd)\n", x);
    return 0;
}
