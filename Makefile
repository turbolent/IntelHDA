#
# Generated-style OPENSTEP DriverKit bundle makefile.
#

NAME = IntelHDA

PROJECTVERSION = 1.1
LANGUAGE = English

LOCAL_RESOURCES = Localizable.strings

GLOBAL_RESOURCES = Default.table

CFILES = IntelHDA_bundle_stub.c

TOOLS = IntelHDA_reloc.tproj

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = bundle.make
SOURCEMODE = 444

BUNDLE_EXTENSION = config

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
