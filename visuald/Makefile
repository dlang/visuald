# This file is part of Visual D
#
# Visual D integrates the D programming language into Visual Studio
# Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
#
# License for redistribution is given by the Artistic License 2.0
# see file LICENSE for further details

PROJECT = visuald

XMLP = ../../xmlp/xmlp
XMLP_SRC = $(XMLP)/compatible.d $(XMLP)/delegater.d $(XMLP)/except.d \
           $(XMLP)/format.d $(XMLP)/input.d $(XMLP)/pieceparser.d \
           $(XMLP)/xmldom.d $(XMLP)/xmlrules.d \
           $(XMLP)/../inrange/instream.d $(XMLP)/../inrange/instring.d \
           $(XMLP)/../inrange/recode.d
# $(XMLP)/recode.d 

SRC = dlangsvc.d dpackage.d register.d simplelexer.d comutil.d \
      logutil.d dllmain.d dproject.d hierarchy.d config.d expansionprovider.d \
      hierutil.d chiernode.d chiercontainer.d propertypage.d build.d \
      completion.d trackprojectdocument.d vscommands.d winctrl.d \
      stringutil.d fileutil.d xmlwrap.d dimagelist.d pkgutil.d \
      intellisense.d oledatasource.d searchsymbol.d windows.d wmmsg.d \
      profiler.d simpleparser.d colorizer.d viewfilter.d

RSRC = resources/dimagelist.bmp resources/pkgcmd.cto resources/resources.h \
       resources/DAboutLogo.ico resources/GroupByType.ico resources/CombineColumns.ico \
       resources/AlternateRowColor.ico resources/closeOnReturn.ico \
       resources/Caseinsensitive.ico resources/CaseSensitive.ico \
       resources/SearchSymbol.ico resources/SearchFile.ico resources/RegExp.ico \
       resources/WholeWord.ico resources/DAboutBox.ico \
       resources/ascend.ico resources/descend.ico \
       resources/refresh.ico resources/removetrace.ico resources/settrace.ico \
       resources/fulldeco.ico resources/faninout.ico

#      $(XMLP_SRC) $(IDL_SRC)
#      vsinterfaces.d vstrackprojectdocuments2.d vsshlids.d variant.d dte.d 
RC  = visuald.rc
DEF = visuald.def


DBGDIR = ..\bin\Debug
RELDIR = ..\bin\Release

DBGRES = $(DBGDIR)\visuald.res
RELRES = $(RELDIR)\visuald.res

DMD = c:\l\dmd2\windows\bin\dmd.exe
# DMD = m:\s\d\dmd\src_org\dmd_pdb.exe
CV2PDB = ..\..\..\cv2pdb\trunk\bin\Debug\cv2pdb.exe

VSISDK = c:\l\vs9SDK
CTC = $(VSISDK)\VisualStudioIntegration\Tools\Bin\CTC.exe

LIB = ..\sdk\lib
OPTLINKS = /SCANLIB

DBG_VSI_LIB = $(DBGDIR)/vsi.lib 
REL_VSI_LIB = $(RELDIR)/vsi.lib 

DFLAGS = -d -L/DELEXECUTABLE -L/LINENUMBERS -I.. -J.. -Jresources
# -version=LOGSEMANTIC  -L/IMPLIB -L/LINENUMBERS -I../../xmlp 

LIBS = phobos.lib ..\sdk\lib\comctl32.lib uuid.lib advapi32.lib comdlg32.lib \
	ole32.lib oleaut32.lib user32.lib shell32.lib gdi32.lib

DEPS = Makefile ..\VERSION $(DMD)

all: debug
# lexer exe

release: $(RELDIR)\$(PROJECT).dll
debug:   $(DBGDIR)\$(PROJECT).dll
exe:     $(DBGDIR)\$(PROJECT).exe

######################
# dll
$(DBGDIR)\$(PROJECT).dll : $(DBGDIR)\$(PROJECT)_cv.dll
	"$(CV2PDB)" -D2.043 $? $@

#-mixin=$(DBGDIR)\$(PROJECT).mixin
$(DBGDIR)\$(PROJECT)_cv.dll : $(SRC) $(DEF) $(DBGRES) $(DBG_VSI_LIB) $(DEPS)
	"$(DMD)" -of$@ -Xf$(DBGDIR)\$(PROJECT).json -g -debug $(DFLAGS) -map $@.map @<<
		$(SRC) $(DBG_VSI_LIB) $(LIBS) $(DEF) $(DBGRES)
<<NOKEEP

$(RELDIR)\$(PROJECT).dll : $(RELDIR)\$(PROJECT)_cv.dll
	"$(CV2PDB)" -D2.043 $? $@

$(RELDIR)\$(PROJECT)_cv.dll : $(SRC) $(DEF) $(RELRES) $(REL_VSI_LIB) $(DEPS)
	"$(DMD)" -of$@ -O -inline -release -g $(DFLAGS) -map $@.map @<<
		$(SRC) $(REL_VSI_LIB) $(LIBS) $(DEF) $(RELRES)
<<NOKEEP

$(DBGRES) : $(RC) $(RSRC)
	rc /fo$(DBGRES) $(RC)

$(RELRES) : $(RC) $(RSRC)
	rc /fo$(RELRES) $(RC)

resources\pkgcmd.cto: resources\pkgcmd.ctc
	"$(CTC)" $? $@ -Ccl -I.

######################
$(DBGDIR)\$(PROJECT).exe : $(DBGDIR)\$(PROJECT)_cv.exe
	"$(CV2PDB)" $? $@

$(DBGDIR)\$(PROJECT)_cv.exe : $(SRC) $(DBG_VSI_LIB) Makefile
	"$(DMD)" -of$@ -g -unittest -debug -version=MAIN $(DFLAGS) @<<
		$(SRC) $(DBG_VSI_LIB) $(LIBS)
<<NOKEEP

######################

REGIT = c:\l\vs9SDK\VisualStudioIntegration\Tools\Bin\RegIt.exe
HIVE  = Software\Microsoft\VisualStudio\9.0D

reg:
	$(REGIT) /root:$(HIVE) /ranu $(DBGDIR)\$(PROJECT).dll

unreg:
	$(REGIT) /root:$(HIVE) /ranu /u $(DBGDIR)\$(PROJECT).dll
