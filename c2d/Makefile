
DMD2D_SRC  = dmd2d.d tokenizer.d
DMDGEN_SRC = dmdgen.d dlist.d pp.d ast.d dgutil.d tokenizer.d tokutil.d
J2D_SRC    = j2d.d tokenizer.d dlist.d tokutil.d dgutil.d 
IDL2D_SRC  = idl2d.d tokenizer.d dlist.d tokutil.d dgutil.d 

DBGDIR = ..\bin\Debug
RELDIR = ..\bin\Release

# DMD = c:\l\dmd-1.056\windows\bin\dmd.exe
# DMD = c:\l\dmd-2.041\windows\bin\dmd.exe
# DMD = c:\l\dmd-2.041b\windows\bin\dmd.exe
DMD = m:\s\d\dmd\src_org\dmd_pdb.exe
# DMD = c:\l\dmd-2.035\windows\bin\dmd.exe
LINK = c:\l\dmd-2.035\windows\bin\link.exe
# DMDPATH = c:\l\dmd-1.039\dmd
# LIBS = $(DMDPATH)\lib
CV2PDB = ..\..\cv2pdb\trunk\bin\Debug\cv2pdb.exe

DFLAGS = -L/DELEXECUTABLE -d
# -version=LOGSEMANTIC  -L/IMPLIB -L/LINENUMBERS 

dmdgen: dmdgen_debug
dmd2d:  dmd2d_debug
j2d:    j2d_debug
idl2d:  idl2d_debug
# lexer exe

dmd2d_release: $(RELDIR)\dmd2d.exe
dmd2d_debug:   $(DBGDIR)\dmd2d.exe

dmdgen_release: $(RELDIR)\dmdgen.exe
dmdgen_debug:   $(DBGDIR)\dmdgen.exe

j2d_release: $(RELDIR)\j2d.exe
j2d_debug:   $(DBGDIR)\j2d.exe

idl2d_release: $(RELDIR)\idl2d.exe
idl2d_debug:   $(DBGDIR)\idl2d.exe

compile:
	$(DMD) -d -debug -g -c dmd1.d dmd2.d dmd3.d dmd4.d dmd2dport.d 
	$(LINK) /NODEBUGTYPES dmd1 dmd3 dmd4 /DEBUGTYPES dmd2 dmd2dport,dmd.exe,,kernel32.lib+user32.lib/CO/NOI;
	$(CV2PDB) dmd.exe dmd_pdb.exe

compile_dmd:
	nmake -f Makefile.dmdgen

#	$(DMD) -d -debug -g dmd.d dmd2dport.d phobos.lib shell32.lib
	
######################
# dmd2d
$(DBGDIR)\dmd2d.exe : $(DBGDIR)\dmd2d_cv.exe
	$(CV2PDB) -D2 $? $@

$(DBGDIR)\dmd2d_cv.exe : $(DMD2D_SRC) Makefile
	$(DMD) -of$@ -map $@.map -g -unittest $(DFLAGS) @<<
		$(DMD2D_SRC) phobos.lib
<<NOKEEP

$(RELDIR)\dmd2d.exe : $(DMD2D_SRC) Makefile
	$(DMD) -of$@ -map $@.map -O $(DFLAGS) @<<
		$(DMD2D_SRC) phobos.lib
<<NOKEEP


######################
# dmdgen
$(DBGDIR)\dmdgen.exe : $(DBGDIR)\dmdgen_cv.exe
	$(CV2PDB) $? $@

$(DBGDIR)\dmdgen_cv.exe : $(DMDGEN_SRC) Makefile
	$(DMD) -of$@ -map $@.map -g -unittest -version=V2 $(DFLAGS) @<<
		$(DMDGEN_SRC) phobos.lib
<<NOKEEP

$(RELDIR)\dmdgen.exe : $(DMDGEN_SRC) Makefile
	$(DMD) -of$@ -map $@.map -O -version=V2 $(DFLAGS) @<<
		$(DMDGEN_SRC) phobos.lib
<<NOKEEP

######################
# j2d
$(DBGDIR)\j2d.exe : $(DBGDIR)\j2d_cv.exe
	$(CV2PDB) $? $@

$(DBGDIR)\j2d_cv.exe : $(J2D_SRC) Makefile
	$(DMD) -of$@ -map $@.map -g -unittest -version=Java $(DFLAGS) @<<
		$(J2D_SRC) phobos.lib
<<NOKEEP

$(RELDIR)\j2d.exe : $(J2D_SRC) Makefile
	$(DMD) -of$@ -map $@.map -O -version=Java $(DFLAGS) @<<
		$(J2D_SRC) phobos.lib
<<NOKEEP

######################
# idl2d
$(DBGDIR)\idl2d.exe : $(DBGDIR)\idl2d_cv.exe
	$(CV2PDB) $? $@

$(DBGDIR)\idl2d_cv.exe : $(IDL2D_SRC) Makefile
	$(DMD) -of$@ -map $@.map -g -unittest -version=IDL $(DFLAGS) @<<
		$(IDL2D_SRC) phobos.lib
<<NOKEEP

$(RELDIR)\idl2d.exe : $(IDL2D_SRC) Makefile
	$(DMD) -of$@ -map $@.map -O -version=IDL $(DFLAGS) @<<
		$(IDL2D_SRC) phobos.lib
<<NOKEEP

