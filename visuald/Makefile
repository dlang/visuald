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

VDC = ../vdc
VDC_SRC = $(VDC)/parser/aggr.d \
        $(VDC)/parser/decl.d \
        $(VDC)/parser/engine.d \
        $(VDC)/parser/expr.d \
        $(VDC)/parser/iasm.d \
        $(VDC)/parser/misc.d \
        $(VDC)/parser/mod.d \
        $(VDC)/parser/stmt.d \
        $(VDC)/parser/tmpl.d \
        $(VDC)/ast/aggr.d \
        $(VDC)/ast/decl.d \
        $(VDC)/ast/expr.d \
        $(VDC)/ast/misc.d \
        $(VDC)/ast/mod.d \
        $(VDC)/ast/stmt.d \
        $(VDC)/ast/tmpl.d \
        $(VDC)/ast/node.d \
        $(VDC)/ast/all.d \
        $(VDC)/ast/iasm.d \
        $(VDC)/ast/type.d \
        $(VDC)/ast/writer.d \
        $(VDC)/util.d \
        $(VDC)/vdserver.d \
        $(VDC)/ivdserver.d \
        $(VDC)/semantic.d \
        $(VDC)/interpret.d \
        $(VDC)/parsertest.d \
        $(VDC)/logger.d \
        $(VDC)/versions.d \
        $(VDC)/lexer.d

RSGC_SRC = ../rsgc/gc.d ../rsgc/gcx.d ../rsgc/gcstats.d ../rsgc/gcalloc.d ../rsgc/gcbits.d

STDEXT_SRC = ../stdext/file.d ../stdext/array.d ../stdext/path.d ../stdext/util.d \
             ../stdext/string.d ../stdext/com.d
# FRED_SRC = ../stdext/fred.d ../stdext/fred_uni.d ../stdext/regionallocator.d

C2D_SRC = ../c2d/cpp2d.d ../c2d/ast.d ../c2d/dlist.d ../c2d/dgutil.d \
          ../c2d/pp.d ../c2d/tokenizer.d ../c2d/tokutil.d
          
SRC = workaround.d \
      config.d dlangsvc.d dpackage.d register.d comutil.d \
      logutil.d dllmain.d dproject.d hierarchy.d expansionprovider.d \
      hierutil.d chiernode.d chiercontainer.d propertypage.d build.d \
      completion.d trackprojectdocument.d vscommands.d winctrl.d \
      stringutil.d fileutil.d xmlwrap.d dimagelist.d pkgutil.d \
      intellisense.d oledatasource.d searchsymbol.d windows.d wmmsg.d \
      profiler.d simpleparser.d colorizer.d viewfilter.d lexutil.d \
      tokenreplace.d tokenreplacedialog.d library.d \
      help.d cppwizard.d vdserverclient.d
# $(STDEXT_SRC)
# $(RSGC_SRC)

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

# DMD2 = c:\l\dmd2\windows\bin\dmd.exe
DMD2 = m:\s\d\dmd2\dmd\src\dmd_pdb.exe
CV2PDB = ..\..\..\cv2pdb\trunk\bin\Debug\cv2pdb.exe

WINSDK = $(WINDOWSSDKDIR:\=/)
VSISDK = c:\l\vs9SDK
CTC = $(VSISDK)\VisualStudioIntegration\Tools\Bin\CTC.exe

LIB = ..\sdk\lib
OPTLINKS = /SCANLIB

DBG_VSI_LIB = $(DBGDIR)/vsi.lib 
REL_VSI_LIB = $(RELDIR)/vsi.lib 

C2D_LIB = c2d_vd.lib 
STDEXT_LIB = stdext.lib 

DFLAGS = -d -L/DELEXECUTABLE -L/LINENUMBERS -I.. -J.. -Jresources -L/MAP:FULL
# -version=LOGSEMANTIC  -L/IMPLIB -L/LINENUMBERS -I../../xmlp 

LIBS = phobos.lib ..\sdk\lib\comctl32.lib uuid.lib advapi32.lib comdlg32.lib \
	ole32.lib oleaut32.lib user32.lib shell32.lib gdi32.lib

DEPS = Makefile ..\VERSION $(DMD2)

all: debug
# lexer exe

release: $(RELDIR)\$(PROJECT).dll
debug:   $(DBGDIR)\$(PROJECT).dll
exe:     $(DBGDIR)\$(PROJECT).exe

######################
# dll
$(DBGDIR)\$(PROJECT).dll : $(DBGDIR)\$(PROJECT)_cv.dll
	"$(CV2PDB)" -D2.043 $? $@

$(DBGDIR)\vdc.lib : $(VDC_SRC) Makefile
	"$(DMD2)" -of$@ -lib -g $(DFLAGS) @<<
		$(VDC_SRC)
<<NOKEEP

$(DBGDIR)\$(C2D_LIB) : $(C2D_SRC) Makefile
	"$(DMD2)" -of$@ -lib -g $(DFLAGS) @<<
		$(C2D_SRC)
<<NOKEEP

$(DBGDIR)\$(STDEXT_LIB) : $(STDEXT_SRC) Makefile
	"$(DMD2)" -of$@ -lib -g $(DFLAGS) @<<
		$(STDEXT_SRC)
<<NOKEEP

#-mixin=$(DBGDIR)\$(PROJECT).mixin
$(DBGDIR)\$(PROJECT)_cv.dll : $(SRC) $(DEF) $(DBGRES) $(DBG_VSI_LIB) $(DBGDIR)\vdc.lib $(DBGDIR)\$(C2D_LIB) $(DBGDIR)\$(STDEXT_LIB) $(DEPS)
	"$(DMD2)" -of$@ -Xf$(DBGDIR)\$(PROJECT).json -g -debug $(DFLAGS) -map $@.map @<<
		$(SRC) $(DBG_VSI_LIB) $(LIBS) $(DEF) $(DBGRES) $(DBGDIR)\vdc.lib $(DBGDIR)\$(C2D_LIB) $(DBGDIR)\$(STDEXT_LIB)
<<NOKEEP

$(DBGDIR)\vdserver.exe : ..\vdc\vdserverfactory.d $(DBGDIR)\$(STDEXT_LIB) $(DBGDIR)\vdc.lib $(DBG_VSI_LIB) $(DBGDIR)\vdserver.res Makefile
	"$(DMD2)" -of$@_cv -g $(DFLAGS) $(DBGDIR)\vdc.lib ..\vdc\vdserverfactory.d $(DBGDIR)\vdserver.res $(DBGDIR)\$(STDEXT_LIB) $(DBG_VSI_LIB) ole32.lib oleaut32.lib -L/SUBSYSTEM:WINDOWS
	"$(CV2PDB)" $@_cv $@

$(DBGDIR)\cpp2d.exe : $(DBGDIR)\$(C2D_LIB) ..\c2d\cpp2d_main.d $(DBGDIR)\$(STDEXT_LIB) Makefile
	"$(DMD2)" -of$@ -g $(DFLAGS) $(DBGDIR)\$(C2D_LIB) ..\c2d\cpp2d_main.d $(DBGDIR)\$(STDEXT_LIB)

#-----
$(RELDIR)\$(PROJECT).dll : $(RELDIR)\$(PROJECT)_cv.dll
	"$(CV2PDB)" -D2.043 $? $@

$(RELDIR)\vdc.lib : $(VDC_SRC) Makefile
	"$(DMD2)" -of$@ -O -inline -release -lib -g $(DFLAGS) @<<
		$(VDC_SRC)
<<NOKEEP

INLINE=-inline
# -O 
$(RELDIR)\$(C2D_LIB) : $(C2D_SRC) Makefile
	"$(DMD2)" -of$@ $(INLINE) -release -lib -g $(DFLAGS) @<<
		$(C2D_SRC)
<<NOKEEP

$(RELDIR)\$(STDEXT_LIB) : $(STDEXT_SRC) Makefile
	"$(DMD2)" -of$@ $(INLINE) -release -lib -g $(DFLAGS) @<<
		$(STDEXT_SRC)
<<NOKEEP

# -c -od$(RELDIR)
$(RELDIR)\$(PROJECT)_cv.dll : $(SRC) $(DEF) $(RELRES) $(REL_VSI_LIB) $(RELDIR)\vdc.lib $(RELDIR)\$(C2D_LIB) $(RELDIR)\$(STDEXT_LIB) $(DEPS)
	"$(DMD2)" -of$@ -O $(INLINE) -release -g $(DFLAGS) -map $@.map @<<
		$(SRC) $(REL_VSI_LIB) $(LIBS) $(DEF) $(RELRES) $(RELDIR)\vdc.lib $(RELDIR)\$(C2D_LIB) $(RELDIR)\$(STDEXT_LIB)
<<NOKEEP

$(RELDIR)\vdserver.exe : ..\vdc\vdserverfactory.d $(RELDIR)\$(STDEXT_LIB) $(REL_VSI_LIB) $(RELDIR)\vdc.lib $(RELDIR)\vdserver.res Makefile
	"$(DMD2)" -of$@_cv -g -O $(INLINE) -release $(DFLAGS) $(RELDIR)\vdc.lib ..\vdc\vdserverfactory.d $(RELDIR)\vdserver.res $(REL_VSI_LIB) $(RELDIR)\$(STDEXT_LIB) ole32.lib oleaut32.lib -L/SUBSYSTEM:WINDOWS
	"$(CV2PDB)" $@_cv $@

$(RELDIR)\cpp2d.exe : $(RELDIR)\$(C2D_LIB) ..\c2d\cpp2d_main.d $(RELDIR)\$(STDEXT_LIB) Makefile
	"$(DMD2)" -of$@ -O $(INLINE) -release $(DFLAGS) $(RELDIR)\$(C2D_LIB) ..\c2d\cpp2d_main.d $(RELDIR)\$(STDEXT_LIB)

#-----
$(DBGRES) : $(RC) $(RSRC)
	rc /fo$(DBGRES) $(RC)

$(RELRES) : $(RC) $(RSRC)
	rc /fo$(RELRES) $(RC)

resources\pkgcmd.cto: resources\pkgcmd.ctc
	"$(CTC)" $? $@ -Ccl -I.

#-----
$(DBGDIR)\vdserver.tlb : ..\vdc\vdserver.idl
	midl /D _DEBUG /nologo /char signed /env win32 /Oicf  /out $(DBGDIR) /error stub_data $?
# /I "$(WindowsSdkDir)\Include" 

$(RELDIR)\vdserver.tlb : ..\vdc\vdserver.idl
	midl /nologo /char signed /env win32 /Oicf  /out $(RELDIR) /error stub_data $?

$(DBGDIR)\vdserver.res : ..\vdc\vdserver.rc $(DBGDIR)\vdserver.tlb 
	rc /fo$@ /I$(DBGDIR) ..\vdc\vdserver.rc

$(RELDIR)\vdserver.res : ..\vdc\vdserver.rc $(RELDIR)\vdserver.tlb 
	rc /fo$@ /I$(RELDIR) ..\vdc\vdserver.rc

######################
$(DBGDIR)\$(PROJECT).exe : $(DBGDIR)\$(PROJECT)_cv.exe
	"$(CV2PDB)" $? $@

$(DBGDIR)\$(PROJECT)_cv.exe : $(SRC) $(DBG_VSI_LIB) Makefile
	"$(DMD2)" -of$@ -g -unittest -debug -version=MAIN $(DFLAGS) @<<
		$(SRC) $(DBG_VSI_LIB) $(LIBS)

<<NOKEEP

######################

REGIT = c:\l\vs9SDK\VisualStudioIntegration\Tools\Bin\RegIt.exe
HIVE  = Software\Microsoft\VisualStudio\9.0D

reg:
	$(REGIT) /root:$(HIVE) /ranu $(DBGDIR)\$(PROJECT).dll

unreg:
	$(REGIT) /root:$(HIVE) /ranu /u $(DBGDIR)\$(PROJECT).dll
