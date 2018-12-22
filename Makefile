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
MSBUILD15 = "c:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild" 
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

visuald_test:
	devenv /Project "visuald"   /Build "TestDebug|Win32" visuald_vs10.sln
	bin\TestDebug\VisualD\VisualD.exe

vdserver:
	devenv /Project "vdserver"  /Build "$(CONFIG)|Win32" visuald_vs10.sln

dparser:
	cd vdc\abothe && $(MSBUILD15) vdserver.sln /p:Configuration=Release;Platform="Any CPU" /p:TargetFrameworkVersion=4.5 /p:DefineConstants=NET40 /t:Rebuild
	editbin /STACK:0x800000 bin\Release\DParserCOMServer\DParserCOMServer.exe

dparser_test:
	set PLATFORM="Any CPU" && dotnet test vdc\abothe\VDServer.sln -c Release

fake_dparser:
	if not exist bin\Release\DParserCOMServer\nul md bin\Release\DParserCOMServer
	if exist "$(PROGRAMFILES)\VisualD\dparser\dparser\DParserCOMServer.exe" copy "$(PROGRAMFILES)\VisualD\dparser\dparser\DParserCOMServer.exe" bin\Release\DParserCOMServer
	if exist "$(PROGRAMFILES)\VisualD\dparser\dparser\D_Parser.dll" copy "$(PROGRAMFILES)\VisualD\dparser\dparser\D_Parser.dll" bin\Release\DParserCOMServer
	if not exist bin\Release\DParserCOMServer\DParserCOMServer.exe echo dummy >bin\Release\DParserCOMServer\DParserCOMServer.exe
	if not exist bin\Release\DParserCOMServer\D_Parser.dll echo dummy >bin\Release\DParserCOMServer\D_Parser.dll

vdextension:
	cd vdextensions && $(MSBUILD) vdextensions.csproj /p:Configuration=Release;Platform=x86 /t:Rebuild

visualdwizard:
	cd vdwizard && $(MSBUILD) VisualDWizard.csproj /p:Configuration=Release;Platform=AnyCPU /t:Rebuild

dbuild12:
	cd msbuild\dbuild && devenv /Build "Release|AnyCPU" /Project "dbuild" dbuild.sln
#	cd msbuild\dbuild && $(MSBUILD) dbuild.sln /p:Configuration=Release;Platform="Any CPU" /t:Rebuild

fake_dbuild12:
	if not exist msbuild\dbuild\obj\release\nul md msbuild\dbuild\obj\release
	if exist "$(PROGRAMFILES)\VisualD\msbuild\dbuild.12.0.dll" copy "$(PROGRAMFILES)\VisualD\msbuild\dbuild.12.0.dll" msbuild\dbuild\obj\release
	if not exist msbuild\dbuild\obj\release\dbuild.12.0.dll echo dummy >msbuild\dbuild\obj\release\dbuild.12.0.dll

dbuild14:
	cd msbuild\dbuild && devenv /Build "Release-v14|AnyCPU" /Project "dbuild" dbuild.sln
#	cd msbuild\dbuild && $(MSBUILD) dbuild.sln /p:Configuration=Release;Platform="Any CPU" /t:Rebuild

fake_dbuild14:
	if not exist msbuild\dbuild\obj\release-v14\nul md msbuild\dbuild\obj\release-v14
	if exist "$(PROGRAMFILES)\VisualD\msbuild\dbuild.14.0.dll" copy "$(PROGRAMFILES)\VisualD\msbuild\dbuild.14.0.dll" msbuild\dbuild\obj\release-v14
	if not exist msbuild\dbuild\obj\release-v14\dbuild.14.0.dll echo dummy >msbuild\dbuild\obj\release-v14\dbuild.14.0.dll

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

mago_vs15:
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v140            /target:DebugEngine\MagoNatDE MagoDbg_2010.sln
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=x64;PlatformToolset=v140              /target:DebugEngine\MagoRemote MagoDbg_2010.sln
	cd ..\..\mago && msbuild "/p:Configuration=Release StaticDE;Platform=Win32;PlatformToolset=v140" /target:Expression\MagoNatCC MagoDbg_2010.sln

cv2pdb:
	cd ..\..\cv2pdb\trunk && devenv /Project "cv2pdb"      /Build "Release|Win32" src\cv2pdb_vs12.sln
	cd ..\..\cv2pdb\trunk && devenv /Project "dviewhelper" /Build "Release|Win32" src\cv2pdb_vs12.sln
	cd ..\..\cv2pdb\trunk && devenv /Project "dumplines"   /Build "Release|Win32" src\cv2pdb_vs12.sln

cv2pdb_vs15:
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141 src\cv2pdb.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141 src\dviewhelper\dviewhelper.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141 src\dumplines.vcxproj

dcxxfilt: $(DCXXFILT_EXE)
$(DCXXFILT_EXE): tools\dcxxfilt.d
# no space after Release, it will be part of environment variable
	cd tools && set CONFIG=Release&& build_dcxxfilt

##################################
# create installer

install_release_modules: install_modules dparser dparser_test cv2pdb mago dbuild12 dbuild14 dbuild15

install_vs: install_release_modules install_only

install_vs_no_vs2017:   install_modules fake_dparser cv2pdb mago dbuild12 dbuild14 fake_dbuild15 install_only

install_vs_only_vs2017: install_modules dparser dparser_test cv2pdb_vs15 mago_vs15 fake_dbuild12 fake_dbuild14 dbuild15 install_only

install_modules: prerequisites visuald_vs vdserver vdextension visualdwizard dcxxfilt

install_only:
	if not exist ..\downloads\nul md ..\downloads
	cd nsis && "$(NSIS)\makensis" /V1 "/DCONFIG=$(CONFIG)" visuald.nsi
