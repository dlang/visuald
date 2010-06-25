# This file is part of Visual D
#
# Visual D integrates the D programming language into Visual Studio
# Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
#
# License for redistribution is given by the Artistic License 2.0
# see file LICENSE for further details

include vsi_sources
VSI_SRC = $(SRC) port/servprov.d port/stdole2.d port/msxml.d port/dte.d port/base.d \
	port\vsi.d port\propidl.d port\rpc.d port\string.d

DBGDIR = ..\bin\Debug
RELDIR = ..\bin\Release

# D = c:\l\dmd-1.056
D = c:\l\dmd2
DMD = $D\windows\bin\dmd.exe
# DMD = m:\s\d\dmd\src_org\dmd_pdb.exe
CV2PDB = ..\..\cv2pdb\trunk\bin\Debug\cv2pdb.exe
IMPLIB = c:\l\dmc\bin\implib.exe
COFFIMPLIB = c:\l\dmc\bin\coffimplib.exe

DFLAGS = -d -L/DELEXECUTABLE -I..
# -version=LOGSEMANTIC  -L/IMPLIB -L/LINENUMBERS 

vsi: vsi_debug

vsi_release: $(RELDIR)\vsi.lib
vsi_debug:   $(DBGDIR)\vsi.lib

######################
$(DBGDIR)\vsi.lib : $(VSI_SRC) Makefile vsi_sources $(DMD)
	$(DMD) -of$@ -g -lib $(DFLAGS) @<<
		$(VSI_SRC)
<<NOKEEP

	#echo -of$@ -O -inline -release -g $(DFLAGS) $(VSI_SRC) >cmdline
$(RELDIR)\vsi.lib : $(VSI_SRC) Makefile vsi_sources $(DMD)
	$(DMD) -of$@ -lib -O -inline -release $(DFLAGS) @<<
		$(VSI_SRC)
<<NOKEEP

######################
WINSDK = $(PROGRAMFILES)\Microsoft SDKs\Windows\v6.0A

WIN_LIBS = lib\kernel32.lib lib\user32.lib lib\winspool.lib lib\advapi32.lib \
	lib\comdlg32.lib lib\gdi32.lib lib\ole32.lib lib\rpcrt4.lib lib\shell32.lib lib\winmm.lib \
	lib\wsock32.lib lib\comctl32.lib lib\oleaut32.lib lib\ws2_32.lib lib\odbc32.lib
# lib\ctl3d32.lib
# lib\uuid.lib 
# WINDIR = c:\windows\system32

sdk_libs: Makefile
	if not exist lib\nul md lib
	for %f in ($(WIN_LIBS)) do @( $(COFFIMPLIB) "$(WINSDK)\%f" %f )
	@echo $(WIN_LIBS) >sdk_libs

libs: sdk_libs

#kernel32.lib : kernel32.dll
#	echo $(IMPLIB) $@ $<
	
# $(WIN_LIBS) : Makefile
