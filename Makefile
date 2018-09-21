#
# master makefile to build a Visual D release
# for development, load visuald_vs10.sln in VS2013+
#
# use this Makefile with Microsofts nmake
#
# prerequisites:
#  Visual Studio 2013/2015/2017 with Visual D installed
#  Visual Studio Integration SDK 2013+
#  DMD 2.071 or newer
#  http://ftp.digitalmars.com/coffimplib.zip
# installer:
#  NSIS
#  ..\..\mago
#  ..\..\cv2pdb\trunk
#  ..\..\binutils-2.25

# targets used during the build process (see appveyor.yml):
# prerequisites
# visuald_vs
# install_vs, install_vs_fake_dbuild15

##############################################################
# update the following variables to match the installation 
# paths on your system or pass on the command line to nmake

NSIS    = $(PROGRAMFILES)\NSIS
MSBUILD = msbuild
CONFIG  = Release COFF32

##############################################################
# no more changes should be necessary starting from here

DCXXFILT_EXE = bin\Release\dcxxfilt.exe

all: install_vs

##################################
# compile visuald components

prerequisites:
	devenv /Project "build"     /Build "$(CONFIG)|Win32" visuald_vs10.sln

visuald_vs:
	devenv /Project "visuald"   /Build "$(CONFIG)|Win32" visuald_vs10.sln

vdserver:
	devenv /Project "vdserver"  /Build "$(CONFIG)|Win32" visuald_vs10.sln

dparser:
	cd vdc\abothe && $(MSBUILD) vdserver.sln /p:Configuration=Release;Platform="Any CPU" /p:TargetFrameworkVersion=4.0 /p:DefineConstants=NET40 /t:Rebuild

vdextension:
	cd vdextensions && $(MSBUILD) vdextensions.csproj /p:Configuration=Release;Platform=x86 /t:Rebuild

visualdwizard:
	cd vdwizard && $(MSBUILD) VisualDWizard.csproj /p:Configuration=Release;Platform=AnyCPU /t:Rebuild

dbuild12:
	cd msbuild\dbuild && devenv /Build "Release|AnyCPU" /Project "dbuild" dbuild.sln
#	cd msbuild\dbuild && $(MSBUILD) dbuild.sln /p:Configuration=Release;Platform="Any CPU" /t:Rebuild

dbuild14:
	cd msbuild\dbuild && devenv /Build "Release-v14|AnyCPU" /Project "dbuild" dbuild.sln
#	cd msbuild\dbuild && $(MSBUILD) dbuild.sln /p:Configuration=Release;Platform="Any CPU" /t:Rebuild

dbuild15:
	cd msbuild\dbuild && devenv /Build "Release-v15|AnyCPU" /Project "dbuild" dbuild.sln

fake_dbuild15:
	if not exist msbuild\dbuild\obj\release-v15\nul md msbuild\dbuild\obj\release-v15
	if exist "$(PROGRAMFILES)\VisualD\msbuild\dbuild.15.0.dll" copy "$(PROGRAMFILES)\VisualD\msbuild\dbuild.15.0.dll" msbuild\dbuild\obj\release-v15
	if not exist msbuild\dbuild\obj\release-v15\dbuild.15.0.dll echo dummy >msbuild\dbuild\obj\release-v15\dbuild.15.0.dll

mago:
	cd ..\..\mago && devenv /Build "Release|Win32" /Project "MagoNatDE" magodbg_2010.sln
	cd ..\..\mago && devenv /Build "Release|x64" /Project "MagoRemote" magodbg_2010.sln
	cd ..\..\mago && devenv /Build "Release StaticDE|Win32" /Project "MagoNatCC" magodbg_2010.sln

cv2pdb:
	cd ..\..\cv2pdb\trunk && devenv /Project "cv2pdb"      /Build "Release|Win32" src\cv2pdb_vs12.sln
	cd ..\..\cv2pdb\trunk && devenv /Project "dviewhelper" /Build "Release|Win32" src\cv2pdb_vs12.sln
	cd ..\..\cv2pdb\trunk && devenv /Project "dumplines"   /Build "Release|Win32" src\cv2pdb_vs12.sln

cv2pdb_vs15:
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32 src\cv2pdb.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32 src\dviewhelper\dviewhelper.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32 src\dumplines.vcxproj

dcxxfilt: $(DCXXFILT_EXE)
$(DCXXFILT_EXE): tools\dcxxfilt.d
# no space after Release, it will be part of environment variable
	cd tools && set CONFIG=Release&& build_dcxxfilt

##################################
# create installer

install_vs: install_modules cv2pdb dbuild15 install_only

install_vs_fake_dbuild15: install_modules cv2pdb_vs15 fake_dbuild15 install_only

install_modules: prerequisites visuald_vs vdserver dparser vdextension visualdwizard mago dcxxfilt \
	dbuild12 dbuild14

install_only:
	if not exist ..\downloads\nul md ..\downloads
	cd nsis && "$(NSIS)\makensis" /V1 "/DCONFIG=$(CONFIG)" visuald.nsi
