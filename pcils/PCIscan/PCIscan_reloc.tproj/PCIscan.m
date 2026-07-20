/*
 * PCIscan.m - kernel-side PCI bus enumerator for OPENSTEP/NeXTSTEP i386.
 *
 * Userland on this system cannot execute IN/OUT instructions (verified:
 * SIGILL), so PCI configuration mechanism #1 (0xCF8/0xCFC) can only be
 * driven from kernel context. This loadable kernel driver walks the bus
 * and emits each device's 64-byte configuration header to IOLog, where
 * syslog records it in /usr/adm/messages. The userland front end
 * (pcils) harvests and formats those lines.
 *
 * The scan is driven by the `CALL pciScanEntry 0' line in
 * Load_Commands.sect, which kern_loader executes during the load
 * sequence. That deliberately avoids DriverKit device matching: this
 * module claims no hardware, so nothing would ever probe it.
 *
 * Output grammar (one device = 4 rows of 4 longs):
 *   PCIS BEGIN <version>
 *   PCIS <bus>:<dev>.<fn> <row> <w0> <w1> <w2> <w3>
 *   PCIS END <deviceCount>
 *
 * Strict C89 + NeXT Objective-C (cc 2.7.2.1). Kernel context: no libc.
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

#define PCI_CFG_ADDR	0x0CF8
#define PCI_CFG_DATA	0x0CFC

/*
 * Buses to walk. Bus 0 holds everything on the single-host-bridge
 * machines this targets; a few more cover a PCI-PCI bridge. Probing far
 * beyond what exists is harmless (reads float to all-ones) but slow.
 */
#define PCI_MAX_BUS	8
#define PCI_MAX_DEV	32

#define PCI_HDR_LONGS	16	/* 64-byte standard header */

#define PCIS_VERSION	1

static unsigned long
pciReadConfig(int bus, int dev, int fn, int reg)
{
    unsigned long addr;

    addr = 0x80000000UL
	 | ((unsigned long)(bus & 0xFF) << 16)
	 | ((unsigned long)(dev & 0x1F) << 11)
	 | ((unsigned long)(fn  & 0x07) <<  8)
	 | ((unsigned long)(reg & 0xFC));

    outl((IOEISAPortAddress)PCI_CFG_ADDR, addr);
    return inl((IOEISAPortAddress)PCI_CFG_DATA);
}

/*
 * A slot with no device floats the data lines: reads come back all-ones.
 * Some chipsets return zero instead, so both are treated as empty.
 */
static int
pciSlotPresent(unsigned long vendorDev)
{
    return (vendorDev != 0xFFFFFFFFUL && vendorDev != 0UL);
}

static void
pciDumpFunction(int bus, int dev, int fn)
{
    unsigned long w[PCI_HDR_LONGS];
    int i;

    for (i = 0; i < PCI_HDR_LONGS; i++) {
	w[i] = pciReadConfig(bus, dev, fn, i * 4);
    }

    /*
     * Four longs per line: keeps each IOLog well inside the kernel log
     * line limit, which a single 16-long line would risk truncating.
     */
    for (i = 0; i < PCI_HDR_LONGS; i += 4) {
	IOLog("PCIS %02x:%02x.%x %d %08x %08x %08x %08x\n",
	      bus, dev, fn, i / 4,
	      (unsigned int)w[i],     (unsigned int)w[i + 1],
	      (unsigned int)w[i + 2], (unsigned int)w[i + 3]);
    }
}

static void
pciScanDump(void)
{
    int bus, dev, fn, nfunc, found;
    unsigned long vendorDev, hdrType;

    found = 0;
    IOLog("PCIS BEGIN %d\n", PCIS_VERSION);

    for (bus = 0; bus < PCI_MAX_BUS; bus++) {
	for (dev = 0; dev < PCI_MAX_DEV; dev++) {

	    vendorDev = pciReadConfig(bus, dev, 0, 0x00);
	    if (!pciSlotPresent(vendorDev)) {
		continue;
	    }

	    /* header type bit 7 = multifunction; single-function parts
	     * alias every function to function 0, so asking further
	     * would report the same device eight times. */
	    hdrType = pciReadConfig(bus, dev, 0, 0x0C);
	    nfunc = (((hdrType >> 16) & 0x80UL) != 0) ? 8 : 1;

	    for (fn = 0; fn < nfunc; fn++) {
		vendorDev = pciReadConfig(bus, dev, fn, 0x00);
		if (!pciSlotPresent(vendorDev)) {
		    continue;
		}
		pciDumpFunction(bus, dev, fn);
		found++;
	    }
	}
    }

    IOLog("PCIS END %d\n", found);
}

/*
 * Entry point named by Load_Commands.sect. kern_loader calls this once,
 * with the integer argument from the CALL line, while the server is
 * being initialized. It must have external linkage for kl_ld to resolve
 * the name.
 */
void
pciScanEntry(int arg)
{
    IOLog("PCIscan: scanning (arg %d)\n", arg);
    pciScanDump();
}
