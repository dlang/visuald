#
# master makefile to build visuald from scratch
#
# prerequisites:
#  DMD2
#  Visual Studio 2005/2008/2010
#  Microsoft Platfrom SDK (6.0A)
#  Visual Studio Integration SDK (for VS2008)

# DMD2 = c:\l\dmd-2.042\windows\bin\dmd_rs.exe
DMD2 = m:\s\d\dmd\src_org\dmd_pdb.exe

WINSDK = $(PROGRAMFILES)\Microsoft SDKs\Windows\v6.0A
MSENV  = $(COMMONPROGRAMFILES)\Microsoft Shared\MSEnv
VSISDK = c:\l\vs9SDK
NSIS   = $(PROGRAMFILES)\NSIS

###

BINDIR = bin\Release
IVIEWER = $(WINSDK)\bin\iviewers.dll

TLB2IDL_EXE = $(BINDIR)\tlb2idl.exe
VSI2D_EXE   = $(BINDIR)\vsi2d.exe
VSI_LIB     = $(BINDIR)\vsi.lib
VISUALD     = $(BINDIR)\visuald.dll

all: dte_idl vsi2d package

###########################
# generate idl from olbs
DTE_IDL_PATH=sdk\vsi\idl

dte_idl: $(DTE_IDL_PATH) $(DTE_IDL_PATH)\dte80.idl $(DTE_IDL_PATH)\dte80a.idl $(DTE_IDL_PATH)\dte90.idl

$(DTE_IDL_PATH):
	if not exist $(DTE_IDL_PATH)\nul md $(DTE_IDL_PATH)

sdk\vsi\idl\dte80.idl : $(TLB2IDL_EXE) "$(MSENV)\dte80.olb"
	$(TLB2IDL_EXE) "$(MSENV)\dte80.olb" $@ "$(IVIEWER)"

sdk\vsi\idl\dte80a.idl : $(TLB2IDL_EXE) "$(MSENV)\dte80a.olb"
	$(TLB2IDL_EXE) "$(MSENV)\dte80a.olb" $@ "$(IVIEWER)"

sdk\vsi\idl\dte90.idl : $(TLB2IDL_EXE) "$(MSENV)\dte90.olb"
	$(TLB2IDL_EXE) "$(MSENV)\dte90.olb" $@ "$(IVIEWER)"

$(TLB2IDL_EXE) : tlb2idl\tlb2idl.d
	$(DMD2) -map $@.map -of$@ tlb2idl\tlb2idl.d oleaut32.lib uuid.lib snn.lib kernel32.lib

##################################
# generate VSI d files from h and idl

vsi2d: vsi_dirs sdk\vsi_sources $(VSI_LIB)

VSI2D_SRC = c2d\idl2d.d c2d\tokenizer.d c2d\tokutil.d \
	c2d\dgutil.d c2d\dlist.d 

vsi_dirs:
	if not exist sdk\vsi\nul   md sdk\vsi
	if not exist sdk\win32\nul md sdk\win32

$(VSI2D_EXE) : $(VSI2D_SRC)
	$(DMD2) -map $@.map -of$@ -version=vsi $(VSI2D_SRC)

sdk\vsi_sources: $(VSI2D_EXE)
	$(VSI2D_EXE) -vsi="$(VSISDK)" -win="$(WINSDK)\Include" -dte="$(DTE_IDL_PATH)" -sdk=sdk

$(VSI_LIB) : sdk\vsi_sources
	cd sdk && nmake "DMD=$(DMD2)" vsi_release

##################################
# compile visuald package

package:
	cd visuald && nmake "DMD=$(DMD2)" release

##################################
# create installer

install: dte_idl vsi2d package
	cd nsis && $(NSIS)\makensis /V1 visuald.nsi