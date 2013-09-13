# This file is part of Visual D
#
# Visual D integrates the D programming language into Visual Studio
# Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
#
# Distributed under the Boost Software License, Version 1.0.
# See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

DMD2 = c:\l\dmd-2.055\windows\bin\dmd.exe
# DMD2 = m:\s\d\rainers\windows\bin\dmd.exe
CV2PDB = ..\..\cv2pdb\trunk\bin\Debug\cv2pdb.exe
IMPLIB = c:\l\dmc\bin\implib.exe
COFFIMPLIB = c:\l\dmc\bin\coffimplib.exe

include vsi_sources
VSI_SRC = $(SRC) port/servprov.d port/stdole2.d port/msxml.d port/dte.d port/base.d \
	port\vsi.d port\propidl.d port\rpc.d port\string.d port\in6addr.d port\inaddr.d \
	port\ctype.d

DBGDIR = ..\bin\Debug
RELDIR = ..\bin\Release

FMT = OMF
!IF "$(FMT)" == "COFF"
DFLAGS = -d -I.. -m32ms
!ELSE
DFLAGS = -d -L/DELEXECUTABLE -I..
!ENDIF

# -version=LOGSEMANTIC  -L/IMPLIB -L/LINENUMBERS 

vsi: vsi_debug

vsi_release: $(RELDIR)\vsi.lib
vsi_debug:   $(DBGDIR)\vsi.lib

######################
$(DBGDIR)\vsi.lib : $(VSI_SRC) Makefile vsi_sources $(DMD2)
	$(DMD2) -of$@ -g -lib $(DFLAGS) @<<
		$(VSI_SRC)
<<NOKEEP

	#echo -of$@ -O -inline -release -g $(DFLAGS) $(VSI_SRC) >cmdline
$(RELDIR)\vsi.lib : $(VSI_SRC) Makefile vsi_sources $(DMD2)
	$(DMD2) -of$@ -lib -O -inline -release $(DFLAGS) @<<
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
