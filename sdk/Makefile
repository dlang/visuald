# This file is part of Visual D
#
# Visual D integrates the D programming language into Visual Studio
# Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
#
# License for redistribution is given by the Artistic License 2.0
# see file LICENSE for further details

include vsi_sources
VSI_SRC = $(SRC) port/servprov.d port/stdole2.d port/msxml.d port/dte.d port/base.d \


DBGDIR = ..\bin\Debug
RELDIR = ..\bin\Release

# D = c:\l\dmd-1.056
# D = c:\l\dmd-2.040
# DMD = $D\windows\bin\dmd_pdb.exe
DMD = m:\s\d\dmd\src_org\dmd_pdb.exe
CV2PDB = ..\..\cv2pdb\trunk\bin\Debug\cv2pdb.exe

DFLAGS = -d -L/DELEXECUTABLE -I..
# -version=LOGSEMANTIC  -L/IMPLIB -L/LINENUMBERS 

vsi: vsi_debug

vsi_release: $(RELDIR)\vsi.lib
vsi_debug:   $(DBGDIR)\vsi.lib

######################
# juno
$(DBGDIR)\vsi.lib : $(VSI_SRC) Makefile vsi_sources $(DMD)
	$(DMD) -of$@ -g -lib $(DFLAGS) @<<
		$(VSI_SRC)
<<NOKEEP

$(RELDIR)\vsi.lib : $(VSI_SRC) Makefile vsi_sources $(DMD)
	$(DMD) -of$@ -lib $(DFLAGS) @<<
		$(VSI_SRC)
<<NOKEEP

######################
