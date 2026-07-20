/*
 * nxlogd.c - push the OPENSTEP system log into the NFS share as it is
 * written, so a kernel hang cannot take the evidence with it.
 *
 * When the kernel wedges, /usr/adm/messages on the local disk is
 * useless: syslogd's last writes are still in the buffer cache and the
 * machine never gets to flush them. Writing to the NFS mount instead
 * puts every line on the Linux host's disk before the next one is read,
 * so whatever the driver logged right up to the hang survives on the
 * host and can be read while the target is still dead.
 *
 * Run it on OPENSTEP before any risky driver test:
 *
 *   nohup /tmp/nxlogd &            # defaults below
 *   nxlogd <source> <dest>
 *
 * Strict C89 - NeXT cc 2.7.2.1.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/time.h>

#define DEF_SRC		"/usr/adm/messages"
#define DEF_DST		"/ndrv/logs/kernel.log"

#define POLL_MS		200
#define BUFSZ		4096

extern int open();
extern int read();
extern int write();
extern int close();
extern int fsync();
extern long lseek();
extern int select();

/*
 * Sub-second sleep. NeXTSTEP's libc predates a dependable usleep(), but
 * select() with no descriptors is portable back to 4.2BSD.
 */
static void
napMillis(long ms)
{
    struct timeval tv;

    tv.tv_sec  = ms / 1000L;
    tv.tv_usec = (ms % 1000L) * 1000L;
    (void)select(0, (fd_set *)0, (fd_set *)0, (fd_set *)0, &tv);
}

int
main(int argc, char **argv)
{
    char *srcPath = DEF_SRC;
    char *dstPath = DEF_DST;
    char  buf[BUFSZ];
    int   src, dst, n;
    long  pos;

    if (argc > 1) {
	srcPath = argv[1];
    }
    if (argc > 2) {
	dstPath = argv[2];
    }

    src = open(srcPath, O_RDONLY, 0);
    if (src < 0) {
	fprintf(stderr, "nxlogd: cannot read %s\n", srcPath);
	return 1;
    }

    /* Start from the end: the point is what happens from now on, and
     * copying the whole historical log would bury it. */
    pos = lseek(src, 0L, 2 /* SEEK_END */);

    dst = open(dstPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (dst < 0) {
	fprintf(stderr, "nxlogd: cannot write %s (is /ndrv mounted?)\n",
		dstPath);
	close(src);
	return 1;
    }

    {
	char marker[256];

	sprintf(marker, "=== nxlogd started, following %s from offset %ld"
		" ===\n", srcPath, pos);
	(void)write(dst, marker, strlen(marker));
	(void)fsync(dst);
    }

    for (;;) {
	n = read(src, buf, BUFSZ);
	if (n > 0) {
	    (void)write(dst, buf, n);
	    /*
	     * The whole point of this program: get it onto the server's
	     * disk now, not whenever the cache feels like it.
	     */
	    (void)fsync(dst);
	} else {
	    napMillis(POLL_MS);
	}
    }

    /* not reached */
}
