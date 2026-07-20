#
# pcils - userland front end. Built natively on OPENSTEP with NeXT cc.
#
#   make            build ./pcils
#   make install    also put it in /usr/local/bin
#   make driver     build + install the PCIscan kernel server
#
# The kernel side lives in PCIscan/ and is built by its own (NeXT
# ProjectBuilder) makefiles.

CC     = cc
CFLAGS = -O -Wall
BINDIR = /usr/local/bin
DEVDIR = /private/Devices

all: pcils

pcils: pcils.c
	$(CC) $(CFLAGS) -o pcils pcils.c

install: pcils
	-mkdir $(BINDIR)
	cp pcils $(BINDIR)/pcils
	chmod 755 $(BINDIR)/pcils

driver:
	cd PCIscan; $(MAKE)
	rm -rf $(DEVDIR)/PCIscan.config
	cp -r PCIscan/PCIscan.config $(DEVDIR)/

clean:
	rm -f pcils
	cd PCIscan; $(MAKE) clean
