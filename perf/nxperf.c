/*
 * nxperf.c - bulk TCP throughput measurement, same source on both ends.
 *
 * The point of building this rather than reaching for an existing tool
 * is comparability: the DEC 21041 (10Mb, driven by OPENSTEP's own
 * driver) and the Intel 82547EI (gigabit, driven by ours) get measured
 * by the identical program over the identical path, so the only thing
 * that differs between the two runs is the network card.
 *
 *   server:  nxperf -s [-p port]
 *   client:  nxperf -c <host> [-p port] [-n megabytes] [-b bufsize]
 *                   [-B local-address] [-r]
 *
 *   -r   reverse: the server sends and the client receives, which
 *        measures the other direction.
 *   -B   bind the local end to this address. With two interfaces on one
 *        subnet this is how a run is pinned to the card under test.
 *
 * Both ends print what they measured; believe the receiving end, since
 * a sender only knows what it handed to the kernel.
 *
 * Strict C89, and deliberately old-fashioned sockets: this has to
 * compile with NeXT cc 2.7.2.1 as well as modern gcc. No getaddrinfo,
 * no snprintf, declarations at the top of each block.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netdb.h>

#ifdef __linux__
#include <unistd.h>
#include <arpa/inet.h>
#else
/* 4.3BSD predates socklen_t; accept() takes an int * there. */
typedef int socklen_t;
/* NeXTSTEP's headers do not declare these where modern ones do. */
extern int   close();
extern int   read();
extern int   write();
extern long  inet_addr();
#endif

#define DEF_PORT	9930
#define DEF_MEGS	32
#define DEF_BUFSZ	8192
#define MAX_BUFSZ	65536

static char  buffer[MAX_BUFSZ];

/*
 * Seconds between two samples, as a double. Throughput over a short run
 * is sensitive to timer resolution, hence gettimeofday rather than
 * time().
 */
static double
elapsed(struct timeval *start, struct timeval *end)
{
    double s;

    s = (double)(end->tv_sec - start->tv_sec);
    s += (double)(end->tv_usec - start->tv_usec) / 1000000.0;
    return s;
}

static void
report(const char *what, long bytes, double seconds)
{
    double mbits;

    if (seconds <= 0.0) {
	seconds = 0.000001;
    }
    mbits = ((double)bytes * 8.0) / (seconds * 1000000.0);

    printf("%s: %ld bytes in %.3f s = %.2f Mbit/s (%.2f MB/s)\n",
	   what, bytes, seconds, mbits,
	   ((double)bytes / seconds) / 1048576.0);
    fflush(stdout);
}

/*
 * Read exactly what the peer sends until it closes, counting bytes.
 * Returns the byte count, or -1 on error.
 */
static long
drain(int fd, int bufsz, double *secondsOut)
{
    struct timeval start, end;
    long  total;
    int   n;
    int   started;

    total   = 0L;
    started = 0;

    for (;;) {
	n = read(fd, buffer, bufsz);
	if (n < 0) {
	    perror("read");
	    return -1L;
	}
	if (n == 0) {
	    break;
	}
	if (!started) {
	    /* Start the clock at the first byte, not at accept(): the
	     * connection setup is not what is being measured. */
	    started = 1;
	    (void)gettimeofday(&start, (struct timezone *)0);
	}
	total += (long)n;
    }

    if (!started) {
	(void)gettimeofday(&start, (struct timezone *)0);
    }
    (void)gettimeofday(&end, (struct timezone *)0);
    *secondsOut = elapsed(&start, &end);
    return total;
}

static long
blast(int fd, long bytes, int bufsz, double *secondsOut)
{
    struct timeval start, end;
    long  remaining, total;
    int   want, n;

    memset(buffer, 'x', (size_t)bufsz);

    remaining = bytes;
    total     = 0L;
    (void)gettimeofday(&start, (struct timezone *)0);

    while (remaining > 0L) {
	want = (remaining < (long)bufsz) ? (int)remaining : bufsz;
	n = write(fd, buffer, want);
	if (n < 0) {
	    perror("write");
	    return -1L;
	}
	total     += (long)n;
	remaining -= (long)n;
    }

    (void)gettimeofday(&end, (struct timezone *)0);
    *secondsOut = elapsed(&start, &end);
    return total;
}

static int
runServer(int port, int bufsz, int reverse, long bytes)
{
    struct sockaddr_in me, peer;
    int    listenFd, fd, on;
    socklen_t peerLen;
    long   count;
    double seconds;

    listenFd = socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd < 0) {
	perror("socket");
	return 1;
    }
    on = 1;
    (void)setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR,
		     (char *)&on, sizeof(on));

    memset((char *)&me, 0, sizeof(me));
    me.sin_family      = AF_INET;
    me.sin_addr.s_addr = INADDR_ANY;
    me.sin_port        = htons((unsigned short)port);

    if (bind(listenFd, (struct sockaddr *)&me, sizeof(me)) < 0) {
	perror("bind");
	return 1;
    }
    if (listen(listenFd, 1) < 0) {
	perror("listen");
	return 1;
    }

    printf("nxperf: listening on port %d (%s)\n",
	   port, reverse ? "will send" : "will receive");
    fflush(stdout);

    peerLen = (socklen_t)sizeof(peer);
    fd = accept(listenFd, (struct sockaddr *)&peer, &peerLen);
    if (fd < 0) {
	perror("accept");
	return 1;
    }
    printf("nxperf: connection from %s\n", inet_ntoa(peer.sin_addr));
    fflush(stdout);

    if (reverse) {
	count = blast(fd, bytes, bufsz, &seconds);
	if (count >= 0L) {
	    report("sent", count, seconds);
	}
    } else {
	count = drain(fd, bufsz, &seconds);
	if (count >= 0L) {
	    report("received", count, seconds);
	}
    }

    close(fd);
    close(listenFd);
    return (count < 0L) ? 1 : 0;
}

static int
runClient(char *host, int port, long bytes, int bufsz,
	  char *bindAddr, int reverse)
{
    struct sockaddr_in there, here;
    struct hostent    *hp;
    int    fd;
    long   count;
    double seconds;

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
	perror("socket");
	return 1;
    }

    /*
     * Pinning the local end is what makes a per-card measurement
     * possible when both cards sit on the same subnet.
     */
    if (bindAddr != (char *)0) {
	memset((char *)&here, 0, sizeof(here));
	here.sin_family      = AF_INET;
	here.sin_addr.s_addr = (unsigned long)inet_addr(bindAddr);
	here.sin_port        = 0;

	if (bind(fd, (struct sockaddr *)&here, sizeof(here)) < 0) {
	    perror("bind (local address)");
	    return 1;
	}
	printf("nxperf: bound to local address %s\n", bindAddr);
	fflush(stdout);
    }

    memset((char *)&there, 0, sizeof(there));
    there.sin_family = AF_INET;
    there.sin_port   = htons((unsigned short)port);
    there.sin_addr.s_addr = (unsigned long)inet_addr(host);

    if (there.sin_addr.s_addr == (unsigned long)-1) {
	hp = gethostbyname(host);
	if (hp == (struct hostent *)0) {
	    fprintf(stderr, "nxperf: cannot resolve %s\n", host);
	    return 1;
	}
	memcpy((char *)&there.sin_addr, hp->h_addr, (size_t)hp->h_length);
    }

    if (connect(fd, (struct sockaddr *)&there, sizeof(there)) < 0) {
	perror("connect");
	return 1;
    }

    if (reverse) {
	count = drain(fd, bufsz, &seconds);
	if (count >= 0L) {
	    report("received", count, seconds);
	}
    } else {
	count = blast(fd, bytes, bufsz, &seconds);
	if (count >= 0L) {
	    report("sent", count, seconds);
	}
	/* Let the peer see EOF so its receive timing ends. */
	(void)shutdown(fd, 1);
	(void)drain(fd, bufsz, &seconds);
    }

    close(fd);
    return (count < 0L) ? 1 : 0;
}

static void
usage(void)
{
    fprintf(stderr, "usage: nxperf -s [-p port] [-b bufsize] [-r] [-n MB]\n");
    fprintf(stderr, "       nxperf -c host [-p port] [-n MB] [-b bufsize]"
	    " [-B local-addr] [-r]\n");
    fprintf(stderr, "  -r  reverse direction (server sends)\n");
    fprintf(stderr, "  -B  bind the local end to this address"
	    " (selects the card)\n");
    exit(2);
}

int
main(int argc, char **argv)
{
    int   isServer = 0;
    int   port     = DEF_PORT;
    int   bufsz    = DEF_BUFSZ;
    int   reverse  = 0;
    long  megs     = DEF_MEGS;
    char *host     = (char *)0;
    char *bindAddr = (char *)0;
    int   i;

    for (i = 1; i < argc; i++) {
	if (strcmp(argv[i], "-s") == 0) {
	    isServer = 1;
	} else if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) {
	    host = argv[++i];
	} else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
	    port = atoi(argv[++i]);
	} else if (strcmp(argv[i], "-n") == 0 && i + 1 < argc) {
	    megs = atol(argv[++i]);
	} else if (strcmp(argv[i], "-b") == 0 && i + 1 < argc) {
	    bufsz = atoi(argv[++i]);
	} else if (strcmp(argv[i], "-B") == 0 && i + 1 < argc) {
	    bindAddr = argv[++i];
	} else if (strcmp(argv[i], "-r") == 0) {
	    reverse = 1;
	} else {
	    usage();
	}
    }

    if (bufsz < 1 || bufsz > MAX_BUFSZ) {
	fprintf(stderr, "nxperf: buffer size must be 1..%d\n", MAX_BUFSZ);
	return 2;
    }
    if (!isServer && host == (char *)0) {
	usage();
    }

    if (isServer) {
	return runServer(port, bufsz, reverse, megs * 1048576L);
    }
    return runClient(host, port, megs * 1048576L, bufsz, bindAddr, reverse);
}
