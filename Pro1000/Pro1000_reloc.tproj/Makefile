#
# Pro1000_reloc - kern-loadable relocatable for the Pro1000 driver.
#

NAME = Pro1000_reloc

PROJECTVERSION = 1.1
LANGUAGE = English

CLASSES = Pro1000.m

HFILES =

OTHERSRCS = Makefile Makefile.preamble Makefile.postamble\
            Makefile.driver_preamble Load_Commands.sect

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = tool.make
SOURCEMODE = 444


-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
