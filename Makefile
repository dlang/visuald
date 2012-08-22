#
# master makefile to build visuald from scratch
#
# use this Makefile with Microsofts nmake
#
# prerequisites:
#  DMD2
#  Visual Studio 2005/2008/2010
#  Microsoft Platfrom SDK (6.0A/7.0A/7.1)
#  Visual Studio Integration SDK (for VS2008/VS2010)

##############################################################
# update the following variables to match the installation 
# paths on your system

DMD2 = m:\s\d\rainers\windows\bin\dmd_msc.exe
# DMD2 = c:\l\dmd2\windows\bin\dmd.exe
# DMD2 = c:\l\dmd2beta\windows\bin\dmd.exe
COFFIMPLIB = c:\l\dmc\bin\coffimplib.exe

# avoid trailing '\', it ruins the command line
# WINSDK = $(WINDOWSSDKDIR:\=/)
# WINSDK = $(PROGRAMFILES)\Microsoft SDKs\Windows\v6.0A
WINSDK = $(PROGRAMW6432)\Microsoft SDKs\Windows\v6.0A
# WINSDK = $(PROGRAMFILES)\Microsoft SDKs\Windows\v7.0A
# WINSDK = $(PROGRAMFILES)\Microsoft SDKs\Windows\v7.1
# WINSDK = $(PROGRAMFILES)\Windows Kits\8.0
# WINSDK = c:\l\vs11\Windows Kits\8.0
VSISDK = c:\l\vs9SDK
# VSISDK = c:\l\vs10SDK
# VSISDK = c:\l\vs11\VSSDK
# VSISDK = $(PROGRAMFILES)\Microsoft Visual Studio 2008 SDK
# VSISDK = $(PROGRAMFILES)\Microsoft Visual Studio 2010 SDK
MSENV  = $(COMMONPROGRAMFILES)\Microsoft Shared\MSEnv
NSIS   = $(PROGRAMFILES)\NSIS
CV2PDB = $(PROGRAMFILES)\VisualD\cv2pdb\cv2pdb.exe
ZIP    = c:\u\unix\zip.exe

##############################################################
# no more changes should be necessary starting from here

BINDIR = bin\Release
IVIEWER = $(WINSDK)\bin\iviewers.dll

TLB2IDL_EXE = $(BINDIR)\tlb2idl.exe
PIPEDMD_EXE = $(BINDIR)\pipedmd.exe
FILEMON_DLL = $(BINDIR)\filemonitor.dll
VSI2D_EXE   = $(BINDIR)\vsi2d.exe
VSI_LIB     = $(BINDIR)\vsi.lib
VISUALD     = $(BINDIR)\visuald.dll

all: dte_idl vsi2d package vdserver_exe $(PIPEDMD_EXE) $(FILEMON_DLL)

sdk: dte_idl vsi_dirs sdk\vsi_sources sdk_lib

DBGREL = release

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

$(TLB2IDL_EXE) : tools\tlb2idl.d
	$(DMD2) -map $@.map -of$@ tools\tlb2idl.d oleaut32.lib uuid.lib snn.lib kernel32.lib

$(PIPEDMD_EXE) : tools\pipedmd.d
	$(DMD2) -map $@.map -of$@ tools\pipedmd.d

$(FILEMON_DLL) : tools\filemonitor.d
	$(DMD2) -map $@.map -of$@ -defaultlib=user32.lib -L/ENTRY:_DllMain@12 tools\filemonitor.d

##################################
# generate VSI d files from h and idl

vsi2d: vsi_dirs sdk\vsi_sources vsi_lib 
# $(VSI_LIB)

VSI2D_SRC = c2d\idl2d.d c2d\idl2d_main.d c2d\tokenizer.d c2d\tokutil.d \
	c2d\dgutil.d c2d\dlist.d 

vsi_dirs:
	if not exist sdk\vsi\nul   md sdk\vsi
	if not exist sdk\win32\nul md sdk\win32

$(VSI2D_EXE) : $(VSI2D_SRC)
	$(DMD2) -d -map $@.map -of$@ -version=vsi $(VSI2D_SRC)

sdk\vsi_sources: $(VSI2D_EXE)
	$(VSI2D_EXE) -vsi="$(VSISDK)" -win="$(WINSDK)\Include" -dte="$(DTE_IDL_PATH)" -sdk=sdk

# $(VSI_LIB) : sdk\vsi_sources
vsi_lib:
	cd sdk && nmake "DMD2=$(DMD2)" "WINSDK=$(WINSDK)" "COFFIMPLIB=$(COFFIMPLIB)" vsi_$(DBGREL) libs

sdk_lib:
	cd sdk && nmake "DMD2=$(DMD2)" "WINSDK=$(WINSDK)" "COFFIMPLIB=$(COFFIMPLIB)" libs

##################################
# compile visuald package

package:
	cd visuald && nmake "DMD2=$(DMD2)" "VSISDK=$(VSISDK)" "CV2PDB=$(CV2PDB)" $(DBGREL)

vdserver_exe:
	cd visuald && nmake "DMD2=$(DMD2)" "WINSDK=$(WINSDK)" "VSISDK=$(VSISDK)" "CV2PDB=$(CV2PDB)" ..\$(BINDIR)\vdserver.exe

cpp2d_exe:
	cd visuald && nmake "DMD2=$(DMD2)" "VSISDK=$(VSISDK)" "CV2PDB=$(CV2PDB)" ..\$(BINDIR)\cpp2d.exe
	copy $(BINDIR)\cpp2d.exe ..\downloads

idl2d_exe: $(VSI2D_EXE) 
	copy $(VSI2D_EXE) ..\downloads\idl2d.exe

##################################
# create installer

install: all cpp2d_exe idl2d_exe
	cd nsis && "$(NSIS)\makensis" /V1 visuald.nsi
	"$(ZIP)" -j ..\downloads\visuald_pdb.zip bin\release\visuald.pdb bin\release\vdserver.pdb

install_only:
	cd nsis && "$(NSIS)\makensis" /V1 visuald.nsi

##################################
# clean build results

clean:
	if exist $(BINDIR)\vsi.lib      del $(BINDIR)\vsi.lib
	if exist $(BINDIR)\vdc.lib      del $(BINDIR)\vdc.lib
	if exist $(BINDIR)\stdext.lib   del $(BINDIR)\stdext.lib
	if exist $(BINDIR)\c2d_vd.lib   del $(BINDIR)\c2d_vd.lib
	if exist $(BINDIR)\visuald.dll  del $(BINDIR)\visuald.dll
	if exist $(BINDIR)\vdserver.exe del $(BINDIR)\vdserver.exe
	if exist $(PIPEDMD_EXE)         del $(PIPEDMD_EXE)
	if exist $(FILEMON_DLL)         del $(FILEMON_DLL)

cleanall: clean
	if exist $(TLB2IDL_EXE)         del $(TLB2IDL_EXE)
	if exist $(VSI2D_EXE)           del $(VSI2D_EXE)
	if exist $(DTE_IDL_PATH)\nul   (del /Q $(DTE_IDL_PATH) && rd $(DTE_IDL_PATH))
	if exist sdk\vsi\nul           (del /Q sdk\vsi && rd sdk\vsi)
	if exist sdk\win32\nul         (del /Q sdk\win32 && rd sdk\win32)

