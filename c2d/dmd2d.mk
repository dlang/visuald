#
# dmake makefile
#
# build process:
#  - sed preprocesses *.c to *.cc
#  - gawk -f gendmd2d.awk creates dmd2d.ci (SYSINC=0) from list of .cc files, 
#      using #include "cc-file" and adding header and footer
#  - dmc compiles dmd2d.ci, printing includes into dmd2d.log
#  - gawk -f getsysinc.awk extracts system includes from dmd2d.log into dmd2d.sysinc
#  - gawk -f gendmd2d.awk creates dmd2d.c (SYSINC=1) from list of .cc files, 
#      using #include "cc-file" and adding header and footer
#  - dmc compiles dmd2d.c, writing preprocessor output to dmd2d.pp
#  - sed -f removepp.sed processes dmd2d.pp to dmd2d.cpp
#

def: dmd2d

.KEEP_STATE: yes

GENDIR = gen
DMDSRCDIR = dmd

DMD2D_EXE = ..\bin\debug\dmd2d.exe

DMDIR  = c:\l\dmd\dm
DMC    = $(DMDIR)\bin\dmc.exe
DMMAKE = $(DMDIR)\bin\make.exe

DMD    = c:\l\dmd-2.030\windows\bin\dmd.exe
# DMD = c:\l\dmd-1.043\windows\bin\dmd.exe

#############################
# shortcuts
G = $(GENDIR)
S = $(DMDSRCDIR)

OBJS := $(shell $(DMMAKE) -f echoobj.mak -s echo_obj )

DMD2D_SRC = {$(OBJS:b)}.cc
DMD2D_SRC_NO_SORTED = $(DMD2D_SRC:s/doc.cc//:s/async.cc//:s/cgobj.cc//)
DMD2D_SRC_SORTED = doc.cc async.cc $(DMD2D_SRC_NO_SORTED) cgobj.cc

dmd2d: $G\dmd.exe

$G\dmd.exe: dmd.d dmd2dport.d
  $(DMD) -of$@ -d $<

dmd.d: $G\dmd2d.cpp $(DMD2D_EXE)
  $(DMD2D_EXE) -s -v -o$@ $G\dmd2d.cpp
 
$G\dmd2d.cpp: $G\dmd2d.pp
  sed -f removepp.sed $< >$@
$G\dmd2d.cpp: removepp.sed

$G\dmd2d.c: $S\win32.mak gendmd2d.awk
  echo $(DMD2D_SRC_SORTED) | gawk -f gendmd2d.awk -v SYSINC=1 > $@

$G\dmd2d.ci: $S\win32.mak gendmd2d.awk
  echo $(DMD2D_SRC_SORTED) | gawk -f gendmd2d.awk -v SYSINC=0 > $@

$G\dmd2d.pp: $G\dmd2d.sysinc dmd2d_miss.cpp $G\dmd2d.c $G\{$(OBJS:b)}.cc $S\optab.c
  $(DMC) -e -l$@ -I$S\root;$S\tk;$S\backend;$S;. -cpp -D_DH -DMARS -HO $G\dmd2d.c

$G\dmd2d.sysinc: $G\dmd2d.log getsysinc.awk
  gawk -f getsysinc.awk -v "DMC=$(DMDIR:s/\/\\/)" $< >$@

$G\dmd2d.log: $G\dmd2d.ci $G\{$(OBJS:b)}.cc $S\optab.c
  $(DMC) -e -l$G\dmd2d.ppi -I$S\root;$S\tk;$S\backend;$S;. -cpp -D_DH -DMARS -HO -v2 -c $G\dmd2d.ci >$@
  
###############################

.SOURCE: $S\backend $S\tk $S\root $S

$G\%.cc : %.c             ; sed -e /__file__/d $< >$@

# object file renamed in OBJS list
$G\csymbol.cc : symbol.c  ; sed /__file__/d $< >$@

$G\cgobj.cc : cgobj.c     ; sed -e /__file__/d -e "/struct Loc/,/};/d" $< >$@

$G\evalu8.cc : evalu8.c   ; sed -e /__file__/d -e "s/short sw/return fmodl(x,y)/" -e "/__asm/,/}/d" $< >$@

$G\var.cc : var.c         ; sed -e /__file__/d -e /controlc_saw/d $< >$@

# replace simple list of pairs "a,b," to structured pairs "{a,b},"
$G\entity.cc : entity.c   ; sed -e /__file__/d -e "/static NameId/,/;/s/\([^,]*\),\([^,]*\),/{{\1,\2}},/" $< >$@

