#
# Pro1000 - Intel 82547EI gigabit ethernet driver (P1 reconnaissance).
# Structure follows /NextDeveloper/Examples/DriverKit/SMC16.
#

NAME = Pro1000

PROJECTVERSION = 1.1
LANGUAGE = English

LOCAL_RESOURCES = Localizable.strings

GLOBAL_RESOURCES = Default.table Instance0.table

TOOLS = Pro1000_reloc.tproj

OTHERSRCS = Makefile Makefile.preamble Makefile.postamble

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = bundle.make
INSTALLDIR = /private/Devices
INSTALLFLAGS = -c -s -m 755
SOURCEMODE = 444

BUNDLE_EXTENSION = config


-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
