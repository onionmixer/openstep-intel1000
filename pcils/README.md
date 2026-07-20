# pcils — an lspci for OPENSTEP

Lists the devices on the PCI bus and writes the result to **stdout or a
file**, so it travels cleanly over a remote-execution channel.

```
pcils                      # scan, then print
pcils -o /tmp/pci.txt      # write to a file instead
pcils -v                   # add each device's raw 64-byte config header
pcils -n                   # decode what is already in the log, do not scan
```

If you are installing the gigabit driver, this is how you find the two
values its `Instance0.table` needs — the card's PCI location and its
IRQ.

## Why it is in two pieces

**Userland on this system cannot execute `IN`/`OUT`** — verified, it
raises `SIGILL`. PCI configuration mechanism #1 is reachable only
through I/O ports `0xCF8`/`0xCFC`, so the bus walk has to happen in
kernel context. Hence two parts:

| Part | Where | Job |
|------|-------|-----|
| `PCIscan/` | kernel (loadable kernel server) | Walks the bus through `0xCF8`/`0xCFC` and writes each device's 64-byte configuration header to `IOLog` |
| `pcils.c` | userland | Loads and unloads that module, harvests the dump from the system log, and formats it |

DriverKit's `getPCIConfigSpace:` is not an alternative: it works on a
device description that is already bound to a detected device, which is
of no use for enumerating a bus.

## How the kernel module gets to run

Loading a module with `kl_util -l` does **not** make DriverKit probe it
when it claims no hardware — neither `+probe:` nor `+load` is called.
(That is measured, not assumed.)

The answer is in the load commands:

```
CALL pciScanEntry 0     # kern_loader calls this during initialisation
WIRE                    # keep text and data resident
START                   # start immediately rather than waiting for a port message
```

`CALL` names a global function for `kern_loader` to invoke while the
server is being initialised, which needs no device matching at all —
exactly right for a diagnostic module that claims no hardware. Source:
NextDev, *Writing Loadable Kernel Servers*, Appendix A.

## Building and running

From the host, with the workspace mounted on the target:

```sh
./tools/nx-install-driver.sh openstep-intel1000/pcils/PCIscan
./tools/nx.sh 'cd /tmp && cp /ndrv/openstep-intel1000/pcils/pcils.c . \
    && cc -O -o pcils pcils.c && ./pcils'
```

Two rules are worth stating because breaking either one costs a reboot.

**Never hand-copy a bundle into `/private/Devices`.** If the copy is
truncated you are left with a zero-length bundle, and the next boot puts
`kern_loader` into an infinite loop. `nx-install-driver.sh` verifies the
installed size for exactly this reason.

**Build in `/tmp`, not on the NFS share.** A build scatters `i386_obj/`,
`sym/` and `*.config/` through the tree, and the NFS server behind the
share is single-threaded.

`pcils` adds, loads, **unloads and deletes** the module on every run, so
it leaves nothing resident in the kernel.

## How it works

- Scans buses 0–7, devices 0–31. Functions 1–7 are only read when the
  header type's multifunction bit is set — a single-function part
  mirrors itself into every function number and would otherwise be
  reported eight times.
- Kernel to userland goes through `IOLog` → syslog →
  `/usr/adm/messages`, four longs per line. One line of sixteen risks
  being truncated by the log's line limit.
- The reader scans the whole log and takes **the last complete
  `BEGIN..END` block**, so a log holding several runs still yields the
  most recent scan.
- The name tables cover the parts in this class of machine, the whole
  Intel 8254x gigabit line, and the Intel 8255x (PRO/100) line. The
  last two are labelled explicitly because **8254x and 8255x are
  entirely different MACs** and are easy to confuse by name alone.

## Example output

From the development machine — a Fujitsu Intel 865G box:

```
00:00.0 Host bridge [0600]: Intel 82865G/PE/P Host Bridge [8086:2570] rev 02
00:03.0 PCI bridge [0604]: Intel 82865G/PE/P PCI-to-CSA Bridge [8086:2573] rev 02
        Bridge: primary 00, secondary 02, subordinate 02
02:01.0 Ethernet controller [0200]: Intel 82547EI Gigabit Ethernet (CSA) [8086:1019] rev 00
        Subsystem: [10cf:11bc] Fujitsu
        IRQ 3, pin A
        BAR0: mem  0xe8100000 (32-bit, non-prefetchable)
        BAR2: io   0x2000
03:0b.0 Ethernet controller [0200]: DEC DECchip 21041 (Tulip) 10Mb Ethernet [1011:0014] rev 21
        IRQ 9, pin A
04:00.0 VGA compatible controller [0300]: Matrox MGA G400/G450 [102b:0525] rev 85

11 PCI functions found
```

The gigabit controller's `02:01.0` and `IRQ 3` are what go into the
driver's `Instance0.table`, as `"Location"` and `"IRQ Levels"`.

`"IRQ Levels"` is required on **every** load path, the boot one included
— the hypothesis that booting assigns the interrupt by itself was tested
and disproved. `Configure.app` can set it too; `"Location"` cannot be set
there and has to be written by hand from what `pcils` reports here.
