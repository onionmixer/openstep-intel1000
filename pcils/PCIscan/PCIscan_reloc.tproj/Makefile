#
# PCIscan_reloc - kern-loadable relocatable for the PCIscan driver.
# Modelled on SMC16_reloc.tproj.
#

NAME = PCIscan_reloc

PROJECTVERSION = 1.1
LANGUAGE = English

CLASSES = PCIscan.m

HFILES =

OTHERSRCS = Makefile Makefile.preamble Makefile.postamble\
            Makefile.driver_preamble Load_Commands.sect\
            Unload_Commands.sect

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = tool.make
SOURCEMODE = 444


-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
