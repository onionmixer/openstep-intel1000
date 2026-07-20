/*
 * pcils.c - list PCI devices on OPENSTEP/NeXTSTEP i386, lspci style.
 *
 * Userland cannot execute IN/OUT on this system, so the actual bus walk
 * happens in the PCIscan loadable kernel server (see PCIscan/). This
 * program drives that module through kern_loader, harvests the hex dump
 * it writes to the system log, and decodes it. Output goes to stdout,
 * or to a file with -o, so it travels cleanly over a remote-execution
 * channel such as gcds.
 *
 * Strict C89 - NeXT cc 2.7.2.1. No snprintf, declarations at block top.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_DEVS	64
#define CFG_WORDS	16		/* 64-byte standard header */
#define ROWS		4		/* log rows per device */
#define ALL_ROWS	0x0F		/* bitmask when every row arrived */
#define LINE_MAX	512

#define DEF_LOG		"/usr/adm/messages"
#define DEF_RELOC	"/private/Devices/PCIscan.config/PCIscan_reloc"
#define DEF_SERVER	"PCIscan"
#define KL_UTIL		"/usr/etc/kl_util"

typedef struct {
    int		bus;
    int		dev;
    int		fn;
    int		rowsSeen;
    unsigned long w[CFG_WORDS];
} PciDev;

typedef struct {
    unsigned int id;
    char	*name;
} IdName;

/* ---------------------------------------------------------------- */
/* Names. Deliberately small: the parts this machine family actually  */
/* carries, plus the whole Intel 8254x gigabit line, which is the     */
/* reason this tool exists.                                           */
/* ---------------------------------------------------------------- */

static IdName vendorNames[] = {
    { 0x1000, "LSI Logic" },     { 0x100B, "National Semiconductor" },
    { 0x1002, "ATI" },           { 0x1011, "DEC" },
    { 0x1013, "Cirrus Logic" },  { 0x1022, "AMD" },
    { 0x1039, "SiS" },           { 0x102B, "Matrox" },
    { 0x104C, "Texas Instruments" }, { 0x1095, "Silicon Image" },
    { 0x1102, "Creative Labs" }, { 0x1106, "VIA" },
    { 0x10B7, "3Com" },          { 0x10CF, "Fujitsu" },
    { 0x10DE, "NVIDIA" },        { 0x10EC, "Realtek" },
    { 0x1186, "D-Link" },        { 0x1274, "Ensoniq" },
    { 0x14E4, "Broadcom" },      { 0x3388, "HiNT" },
    { 0x5333, "S3" },
    { 0x8086, "Intel" },         { 0x9004, "Adaptec" },
    { 0x9005, "Adaptec" },
    { 0, 0 }
};

/* keyed vendor<<16 | device */
static IdName deviceNames[] = {
    /* Intel 8254x gigabit family - the pro1000 driver's target set */
    { 0x80861000, "82542 Gigabit Ethernet" },
    { 0x80861001, "82543GC Gigabit Ethernet (fiber)" },
    { 0x80861004, "82543GC Gigabit Ethernet (copper)" },
    { 0x80861008, "82544EI Gigabit Ethernet (copper)" },
    { 0x80861009, "82544EI Gigabit Ethernet (fiber)" },
    { 0x8086100C, "82544GC Gigabit Ethernet (copper)" },
    { 0x8086100D, "82544GC Gigabit Ethernet (LOM)" },
    { 0x8086100E, "82540EM Gigabit Ethernet" },
    { 0x8086100F, "82545EM Gigabit Ethernet (copper)" },
    { 0x80861010, "82546EB Gigabit Ethernet (copper)" },
    { 0x80861011, "82545EM Gigabit Ethernet (fiber)" },
    { 0x80861012, "82546EB Gigabit Ethernet (fiber)" },
    { 0x80861013, "82541EI Gigabit Ethernet" },
    { 0x80861014, "82541ER Gigabit Ethernet (LOM)" },
    { 0x80861015, "82540EM Gigabit Ethernet (LOM)" },
    { 0x80861016, "82540EP Gigabit Ethernet (LOM)" },
    { 0x80861017, "82540EP Gigabit Ethernet" },
    { 0x80861018, "82541EI Gigabit Ethernet (mobile)" },
    { 0x80861019, "82547EI Gigabit Ethernet (CSA)" },
    { 0x8086101A, "82547EI Gigabit Ethernet (mobile)" },
    { 0x8086101D, "82546EB Gigabit Ethernet (quad copper)" },
    { 0x8086101E, "82540EP Gigabit Ethernet (mobile)" },
    { 0x80861026, "82545GM Gigabit Ethernet (copper)" },
    { 0x80861027, "82545GM Gigabit Ethernet (fiber)" },
    { 0x80861028, "82545GM Gigabit Ethernet (SerDes)" },
    { 0x80861075, "82547GI Gigabit Ethernet (CSA)" },
    { 0x80861076, "82541GI Gigabit Ethernet" },
    { 0x80861077, "82541GI Gigabit Ethernet (mobile)" },
    { 0x80861078, "82541ER Gigabit Ethernet" },
    { 0x80861079, "82546GB Gigabit Ethernet (copper)" },
    { 0x8086107A, "82546GB Gigabit Ethernet (fiber)" },
    { 0x8086107B, "82546GB Gigabit Ethernet (SerDes)" },
    { 0x8086107C, "82541PI Gigabit Ethernet" },

    /*
     * Intel 8255x fast-ethernet family. This machine also carries a
     * PRO/100, and it must never be mistaken for the gigabit part: it
     * is a completely different MAC (8255x, CU/RU command units) and is
     * NOT what the pro1000 driver targets.
     */
    { 0x80861029, "82559 Ethernet PRO/100 (8255x - FAST ethernet)" },
    { 0x80861030, "82559 InBusiness 10/100 (8255x - FAST ethernet)" },
    { 0x8086103D, "82801DB PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80861050, "82562EZ PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80861051, "82562ET PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80861059, "82551QM PRO/100 (8255x - FAST ethernet)" },
    { 0x80861064, "82562ET/EZ PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80861065, "82562ET/EZ PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80861092, "82562G PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80861209, "82559ER Ethernet (8255x - FAST ethernet)" },
    { 0x80861229, "82557/8/9/0/1 Ethernet PRO/100 (8255x - FAST ethernet)" },
    { 0x80862449, "82801BA/CA/DB/EB PRO/100 VE (8255x - FAST ethernet)" },
    { 0x80862459, "82801E Ethernet (8255x - FAST ethernet)" },
    { 0x8086245D, "82801E Ethernet (8255x - FAST ethernet)" },

    /* Intel 865G (Springdale) + ICH5 - this machine's chipset */
    { 0x80862570, "82865G/PE/P Host Bridge" },
    { 0x80862571, "82865G/PE/P AGP Bridge" },
    { 0x80862572, "82865G Integrated Graphics" },
    { 0x80862573, "82865G/PE/P PCI-to-CSA Bridge" },
    { 0x8086244E, "82801 PCI Bridge" },
    { 0x808624D0, "82801EB/ER LPC Interface (ICH5)" },
    { 0x808624D1, "82801EB SATA Controller" },
    { 0x808624D2, "82801EB/ER USB UHCI #1" },
    { 0x808624D3, "82801EB/ER SMBus Controller" },
    { 0x808624D4, "82801EB/ER USB UHCI #2" },
    { 0x808624D5, "82801EB/ER AC'97 Audio" },
    { 0x808624D7, "82801EB/ER USB UHCI #3" },
    { 0x808624DB, "82801EB/ER IDE Controller" },
    { 0x808624DD, "82801EB/ER USB2 EHCI" },
    { 0x808624DE, "82801EB/ER USB UHCI #4" },

    /* other parts seen on this machine */
    { 0x10110014, "DECchip 21041 (Tulip) 10Mb Ethernet" },
    { 0x102B0525, "MGA G400/G450" },
    { 0x33880021, "HB4 PCI-to-PCI Bridge" },

    { 0, 0 }
};

static IdName classNames[] = {
    { 0x0100, "SCSI storage controller" },
    { 0x0101, "IDE interface" },
    { 0x0106, "SATA controller" },
    { 0x0180, "Mass storage controller" },
    { 0x0200, "Ethernet controller" },
    { 0x0280, "Network controller" },
    { 0x0300, "VGA compatible controller" },
    { 0x0380, "Display controller" },
    { 0x0401, "Multimedia audio controller" },
    { 0x0500, "RAM memory" },
    { 0x0600, "Host bridge" },
    { 0x0601, "ISA bridge" },
    { 0x0604, "PCI bridge" },
    { 0x0607, "CardBus bridge" },
    { 0x0680, "Bridge" },
    { 0x0700, "Serial controller" },
    { 0x0C03, "USB controller" },
    { 0x0C05, "SMBus controller" },
    { 0, 0 }
};

static char *
lookupName(IdName *table, unsigned int key)
{
    int i;

    for (i = 0; table[i].name != 0; i++) {
	if (table[i].id == key) {
	    return table[i].name;
	}
    }
    return 0;
}

static char *
classText(unsigned long classCode)
{
    char *s;

    s = lookupName(classNames, (unsigned int)(classCode >> 8));
    if (s != 0) {
	return s;
    }
    /* fall back to the base class alone */
    s = lookupName(classNames, (unsigned int)((classCode >> 16) << 8));
    return (s != 0) ? s : "Unknown device";
}

/* ---------------------------------------------------------------- */
/* Log harvesting                                                     */
/* ---------------------------------------------------------------- */

static PciDev	devs[MAX_DEVS];
static int	nDevs;
static PciDev	pending[MAX_DEVS];
static int	nPending;

/*
 * Scan the whole log and keep the LAST complete BEGIN..END block, so a
 * log holding several runs (or a duplicate dump) still yields exactly
 * the most recent scan.
 */
static int
harvestLog(char *path, int *countOut)
{
    FILE *f;
    char line[LINE_MAX];
    char *p;
    int  gotBlock;
    int  reported;

    f = fopen(path, "r");
    if (f == 0) {
	fprintf(stderr, "pcils: cannot read %s\n", path);
	return -1;
    }

    gotBlock = 0;
    reported = 0;
    nPending = 0;

    while (fgets(line, sizeof(line), f) != 0) {

	p = strstr(line, "PCIS ");
	if (p == 0) {
	    continue;
	}
	p += 5;

	if (strncmp(p, "BEGIN", 5) == 0) {
	    nPending = 0;
	    continue;
	}

	if (strncmp(p, "END", 3) == 0) {
	    /* commit: this block is complete */
	    memcpy((char *)devs, (char *)pending,
		   sizeof(PciDev) * (size_t)nPending);
	    nDevs = nPending;
	    reported = atoi(p + 3);
	    gotBlock = 1;
	    nPending = 0;
	    continue;
	}

	{
	    int bus, dev, fn, row, i;
	    unsigned long v[ROWS];
	    PciDev *d;

	    if (sscanf(p, "%x:%x.%x %d %lx %lx %lx %lx",
		       &bus, &dev, &fn, &row,
		       &v[0], &v[1], &v[2], &v[3]) != 8) {
		continue;
	    }
	    if (row < 0 || row >= ROWS) {
		continue;
	    }

	    d = 0;
	    for (i = 0; i < nPending; i++) {
		if (pending[i].bus == bus && pending[i].dev == dev
		    && pending[i].fn == fn) {
		    d = &pending[i];
		    break;
		}
	    }
	    if (d == 0) {
		if (nPending >= MAX_DEVS) {
		    continue;
		}
		d = &pending[nPending++];
		memset((char *)d, 0, sizeof(PciDev));
		d->bus = bus;
		d->dev = dev;
		d->fn  = fn;
	    }

	    for (i = 0; i < ROWS; i++) {
		d->w[row * ROWS + i] = v[i];
	    }
	    d->rowsSeen |= (1 << row);
	}
    }

    fclose(f);

    if (!gotBlock) {
	return -1;
    }
    *countOut = reported;
    return 0;
}

/* ---------------------------------------------------------------- */
/* Formatting                                                         */
/* ---------------------------------------------------------------- */

static void
printBar(FILE *out, int index, unsigned long bar)
{
    /* An unimplemented BAR reads as zero. Legacy-mode IDE also leaves
     * its first four BARs as a bare I/O indicator with no address, which
     * is equally uninteresting. */
    if (bar == 0 || (bar & 0xFFFFFFFCUL) == 0) {
	return;
    }

    if (bar & 1UL) {
	fprintf(out, "\tBAR%d: io   0x%04lx\n",
		index, bar & 0xFFFFFFFCUL);
    } else {
	char *width;
	char *pref;

	width = (((bar >> 1) & 3UL) == 2UL) ? "64-bit" : "32-bit";
	pref  = (bar & 8UL) ? "prefetchable" : "non-prefetchable";
	fprintf(out, "\tBAR%d: mem  0x%08lx (%s, %s)\n",
		index, bar & 0xFFFFFFF0UL, width, pref);
    }
}

static void
printDevice(FILE *out, PciDev *d, int verbose)
{
    unsigned int vendor, device;
    unsigned long classCode, rev, headerType;
    char *vName, *dName;
    int i;

    vendor = (unsigned int)(d->w[0] & 0xFFFFUL);
    device = (unsigned int)((d->w[0] >> 16) & 0xFFFFUL);
    classCode  = d->w[2] >> 8;
    rev        = d->w[2] & 0xFFUL;
    headerType = (d->w[3] >> 16) & 0x7FUL;

    vName = lookupName(vendorNames, vendor);
    dName = lookupName(deviceNames,
		       ((unsigned int)vendor << 16) | device);

    fprintf(out, "%02x:%02x.%x %s [%04lx]: %s %s [%04x:%04x] rev %02lx\n",
	    d->bus, d->dev, d->fn,
	    classText(classCode), classCode >> 8,
	    (vName != 0) ? vName : "Unknown vendor",
	    (dName != 0) ? dName : "Unknown device",
	    vendor, device, rev);

    if ((classCode & 0xFFUL) != 0) {
	fprintf(out, "\tProgramming interface 0x%02lx\n", classCode & 0xFFUL);
    }

    if ((d->rowsSeen & ALL_ROWS) != ALL_ROWS) {
	fprintf(out, "\t(incomplete: log rows missing)\n");
	return;
    }

    if (headerType == 1) {
	/* PCI-to-PCI bridge: bus numbers live where BAR2.. would be */
	fprintf(out, "\tBridge: primary %02lx, secondary %02lx, "
		"subordinate %02lx\n",
		d->w[6] & 0xFFUL,
		(d->w[6] >> 8) & 0xFFUL,
		(d->w[6] >> 16) & 0xFFUL);
    } else {
	unsigned int subVendor, subDevice;

	subVendor = (unsigned int)(d->w[11] & 0xFFFFUL);
	subDevice = (unsigned int)((d->w[11] >> 16) & 0xFFFFUL);
	if (d->w[11] != 0) {
	    char *sName;

	    sName = lookupName(vendorNames, subVendor);
	    fprintf(out, "\tSubsystem: [%04x:%04x]%s%s\n",
		    subVendor, subDevice,
		    (sName != 0) ? " " : "",
		    (sName != 0) ? sName : "");
	}
    }

    {
	unsigned long irq, pin;

	irq = d->w[15] & 0xFFUL;
	pin = (d->w[15] >> 8) & 0xFFUL;
	if (pin != 0) {
	    fprintf(out, "\tIRQ %lu, pin %c\n", irq,
		    (char)('A' + (int)pin - 1));
	}
    }

    fprintf(out, "\tCommand 0x%04lx, Status 0x%04lx\n",
	    d->w[1] & 0xFFFFUL, (d->w[1] >> 16) & 0xFFFFUL);

    if (headerType == 0) {
	for (i = 0; i < 6; i++) {
	    printBar(out, i, d->w[4 + i]);
	}
    }

    if (verbose) {
	fprintf(out, "\tConfig header:\n");
	for (i = 0; i < CFG_WORDS; i += 4) {
	    fprintf(out, "\t  %02x: %08lx %08lx %08lx %08lx\n",
		    i * 4, d->w[i], d->w[i + 1],
		    d->w[i + 2], d->w[i + 3]);
	}
    }
}

/* ---------------------------------------------------------------- */

static int
runScan(char *reloc, char *server)
{
    char cmd[LINE_MAX];

    /* A previous run may have left the server registered; both of these
     * are expected to fail on a clean system, so their status is not
     * checked. */
    sprintf(cmd, "%s -u %s > /dev/null 2>&1", KL_UTIL, server);
    system(cmd);
    sprintf(cmd, "%s -d %s > /dev/null 2>&1", KL_UTIL, server);
    system(cmd);

    sprintf(cmd, "%s -a %s > /dev/null 2>&1", KL_UTIL, reloc);
    if (system(cmd) != 0) {
	fprintf(stderr, "pcils: kl_util -a failed for %s\n", reloc);
	return -1;
    }

    sprintf(cmd, "%s -l %s > /dev/null 2>&1", KL_UTIL, server);
    if (system(cmd) != 0) {
	fprintf(stderr, "pcils: kl_util -l failed for %s\n", server);
	return -1;
    }

    /* syslogd writes the log asynchronously; give it a moment before
     * reading back. */
    system("sleep 2");

    /* Leave no resident module behind. */
    sprintf(cmd, "%s -u %s > /dev/null 2>&1", KL_UTIL, server);
    system(cmd);
    sprintf(cmd, "%s -d %s > /dev/null 2>&1", KL_UTIL, server);
    system(cmd);

    return 0;
}

static void
usage(void)
{
    fprintf(stderr,
	"usage: pcils [-n] [-v] [-o outfile] [-f logfile] [-r reloc]\n");
    fprintf(stderr,
	"  -n  do not load the scanner; decode what is already logged\n");
    fprintf(stderr,
	"  -v  also dump each device's raw 64-byte config header\n");
    fprintf(stderr,
	"  -o  write the listing to a file instead of stdout\n");
    fprintf(stderr,
	"  -f  system log to read (default %s)\n", DEF_LOG);
    fprintf(stderr,
	"  -r  scanner relocatable (default %s)\n", DEF_RELOC);
    exit(2);
}

int
main(int argc, char **argv)
{
    char *logPath   = DEF_LOG;
    char *relocPath = DEF_RELOC;
    char *outPath   = 0;
    int   noLoad    = 0;
    int   verbose   = 0;
    int   reported  = 0;
    FILE *out;
    int   i;

    for (i = 1; i < argc; i++) {
	if (strcmp(argv[i], "-n") == 0) {
	    noLoad = 1;
	} else if (strcmp(argv[i], "-v") == 0) {
	    verbose = 1;
	} else if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
	    outPath = argv[++i];
	} else if (strcmp(argv[i], "-f") == 0 && i + 1 < argc) {
	    logPath = argv[++i];
	} else if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
	    relocPath = argv[++i];
	} else {
	    usage();
	}
    }

    if (!noLoad) {
	if (runScan(relocPath, DEF_SERVER) != 0) {
	    return 1;
	}
    }

    if (harvestLog(logPath, &reported) != 0) {
	fprintf(stderr, "pcils: no complete scan found in %s\n", logPath);
	fprintf(stderr, "       (is PCIscan installed? try without -n)\n");
	return 1;
    }

    if (outPath != 0) {
	out = fopen(outPath, "w");
	if (out == 0) {
	    fprintf(stderr, "pcils: cannot write %s\n", outPath);
	    return 1;
	}
    } else {
	out = stdout;
    }

    for (i = 0; i < nDevs; i++) {
	printDevice(out, &devs[i], verbose);
    }

    fprintf(out, "\n%d PCI functions found", nDevs);
    if (reported != nDevs) {
	fprintf(out, " (kernel reported %d)", reported);
    }
    fprintf(out, "\n");

    if (out != stdout) {
	fclose(out);
	fprintf(stderr, "pcils: wrote %s\n", outPath);
    }

    return 0;
}
