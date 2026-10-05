#
# Generated-style OPENSTEP DriverKit bundle makefile.
#

NAME = IntelHDA

PROJECTVERSION = 1.1
LANGUAGE = English

LOCAL_RESOURCES = Localizable.strings

GLOBAL_RESOURCES = Default.table IntelHDA_reloc intelhda-status intelhda-route

CFILES = IntelHDA_bundle_stub.c

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble \
	tools/intelhda-status.m tools/intelhda-route.m

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = bundle.make
SOURCEMODE = 444

BUNDLE_EXTENSION = config

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies

RELOC_SOURCES = IntelHDA_reloc.tproj/IntelHDARouteCore.c \
	IntelHDA_reloc.tproj/IntelHDARouteCore.h \
	IntelHDA_reloc.tproj/IntelHDARouteStatus.h \
	 IntelHDA_reloc.tproj/IntelHDAController.m \
	IntelHDA_reloc.tproj/IntelHDADriver.m \
	IntelHDA_reloc.tproj/IntelHDAMSIPCI.c \
	IntelHDA_reloc.tproj/IntelHDAMSIWork.c \
	IntelHDA_reloc.tproj/IntelHDAInterruptCore.c \
	IntelHDA_reloc.tproj/IntelHDAPlaybackCore.c \
	IntelHDA_reloc.tproj/IntelHDARefillCore.c \
	IntelHDA_reloc.tproj/IntelHDACodecCore.c \
	IntelHDA_reloc.tproj/IntelHDARateCore.c \
	IntelHDA_reloc.tproj/IntelHDAController.h \
	IntelHDA_reloc.tproj/IntelHDADriver.h \
	IntelHDA_reloc.tproj/IntelHDAMSIPCI.h \
	IntelHDA_reloc.tproj/IntelHDAMSIWork.h \
	IntelHDA_reloc.tproj/IntelHDAInterruptCore.h \
	IntelHDA_reloc.tproj/IntelHDAPlaybackCore.h \
	IntelHDA_reloc.tproj/IntelHDARefillCore.h \
	IntelHDA_reloc.tproj/IntelHDACodecCore.h \
	IntelHDA_reloc.tproj/IntelHDARateCore.h \
	IntelHDA_reloc.tproj/IntelHDAStats.h \
	IntelHDA_reloc.tproj/PCIMSI/PCIMSIClient.h \
	IntelHDA_reloc.tproj/PCIMSI/PCIMSICore.h \
	IntelHDA_reloc.tproj/Makefile \
	IntelHDA_reloc.tproj/Makefile.preamble

IntelHDA_reloc: $(RELOC_SOURCES)
	cd IntelHDA_reloc.tproj && /bin/make all
	cp IntelHDA_reloc.tproj/IntelHDA_reloc $@

clean:: clean_reloc

clean_reloc:
	-cd IntelHDA_reloc.tproj && $(MAKE) clean
	-/bin/rm -f IntelHDA_reloc
