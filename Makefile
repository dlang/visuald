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

# nmake doesn't like $(ProgramFiles(x86)), so run this with x86 nmake
PROGRAMFILESX86 = c:\Program Files (x86)

NSIS    = $(PROGRAMFILESX86)\NSIS
!IF !EXIST("$(NSIS)")
NSIS    = c:\p\NSIS-3.04
!ENDIF
MSBUILD = msbuild
MSBUILD15 = "c:\Program Files (x86)\Microsoft Visual Studio\2017\Community\MSBuild\15.0\Bin\msbuild"
!IF !EXIST($(MSBUILD15))
MSBUILD15 = "c:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild"
!ENDIF
!IF !EXIST($(MSBUILD15))
MSBUILD15 = "c:\Program Files (x86)\Microsoft Visual Studio\2019\Preview\MSBuild\Current\Bin\msbuild"
!ENDIF
# CONFIG  = Release LDC
CONFIG  = Release COFF32
CONFIG_X64 = Release COFF32
CONFIG_ARM64 = Release LDC ARM
CONFIG_DMDSERVER = Release COFF32

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

visuald_vs_x64:
	devenv /Project "visuald"   /Build "$(CONFIG_X64)|x64" visuald_vs10.sln

visuald_vs_arm64:
	devenv /Project "visuald"   /Build "$(CONFIG_ARM64)|x64" visuald_vs10.sln

visuald_test:
	devenv /Project "visuald"   /Build "TestDebug|Win32" visuald_vs10.sln
	bin\TestDebug\VisualD\VisualD.exe

vdserver:
	devenv /Project "vdserver"  /Build "$(CONFIG)|Win32" visuald_vs10.sln

dmdserver:
	devenv /Project "dmdserver" /Build "$(CONFIG_DMDSERVER)|x64" visuald_vs10.sln

dmdserver_test:
	devenv /Project "dmdserver" /Build "TestDebug|x64" visuald_vs10.sln

dparser:
	cd vdc\abothe && $(MSBUILD15) vdserver.sln /p:Configuration=Release;Platform="Any CPU" /p:TargetFrameworkVersion=4.5.2 /p:DefineConstants=NET40 /t:Rebuild
	editbin /STACK:0x800000 bin\Release\DParserCOMServer\DParserCOMServer.exe

dparser_test:
	set PLATFORM="Any CPU" && dotnet test vdc\abothe\VDServer.sln -c Release

fake_dparser:
	if not exist bin\Release\DParserCOMServer\nul md bin\Release\DParserCOMServer
	if exist "$(PROGRAMFILESX86)\VisualD\dparser\dparser\DParserCOMServer.exe" copy "$(PROGRAMFILESX86)\VisualD\dparser\dparser\DParserCOMServer.exe" bin\Release\DParserCOMServer
	if exist "$(PROGRAMFILESX86)\VisualD\dparser\dparser\D_Parser.dll" copy "$(PROGRAMFILESX86)\VisualD\dparser\dparser\D_Parser.dll" bin\Release\DParserCOMServer
	if not exist bin\Release\DParserCOMServer\DParserCOMServer.exe echo dummy >bin\Release\DParserCOMServer\DParserCOMServer.exe
	if not exist bin\Release\DParserCOMServer\D_Parser.dll echo dummy >bin\Release\DParserCOMServer\D_Parser.dll

vdextension:
	cd vdextensions && $(MSBUILD) vdextensions.csproj /p:Configuration=Release;Platform=AnyCPU /t:Rebuild

vdext15:
	cd vdextensions && $(MSBUILD) vdext15.csproj /p:Configuration=Release;Platform=AnyCPU /t:Rebuild

visualdwizard:
	cd vdwizard && $(MSBUILD) VisualDWizard.csproj /p:Configuration=Release;Platform=AnyCPU /t:Rebuild

dbuild12:
#	cd msbuild\dbuild && devenv /Build "Release|AnyCPU" /Project "dbuild" dbuild.sln
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release;Platform=AnyCPU /t:Rebuild

fake_dbuild12:
	if not exist msbuild\dbuild\obj\release\nul md msbuild\dbuild\obj\release
	if exist "$(PROGRAMFILESX86)\VisualD\msbuild\dbuild.12.0.dll" copy "$(PROGRAMFILESX86)\VisualD\msbuild\dbuild.12.0.dll" msbuild\dbuild\obj\release
	if not exist msbuild\dbuild\obj\release\dbuild.12.0.dll echo dummy >msbuild\dbuild\obj\release\dbuild.12.0.dll

dbuild14:
#	cd msbuild\dbuild && devenv /Build "Release-v14|AnyCPU" /Project "dbuild" dbuild.sln
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v14;Platform=AnyCPU /t:Rebuild

fake_dbuild14:
	if not exist msbuild\dbuild\obj\release-v14\nul md msbuild\dbuild\obj\release-v14
	if exist "$(PROGRAMFILESX86)\VisualD\msbuild\dbuild.14.0.dll" copy "$(PROGRAMFILESX86)\VisualD\msbuild\dbuild.14.0.dll" msbuild\dbuild\obj\release-v14
	if not exist msbuild\dbuild\obj\release-v14\dbuild.14.0.dll echo dummy >msbuild\dbuild\obj\release-v14\dbuild.14.0.dll

dbuild15:
#	cd msbuild\dbuild && devenv /Build "Release-v15|AnyCPU" /Project "dbuild" dbuild.sln
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v15;Platform=AnyCPU /t:Rebuild

fake_dbuild15:
	if not exist msbuild\dbuild\obj\release-v15\nul md msbuild\dbuild\obj\release-v15
	if exist "$(PROGRAMFILESX86)\VisualD\msbuild\dbuild.15.0.dll" copy "$(PROGRAMFILESX86)\VisualD\msbuild\dbuild.15.0.dll" msbuild\dbuild\obj\release-v15
	if not exist msbuild\dbuild\obj\release-v15\dbuild.15.0.dll echo dummy >msbuild\dbuild\obj\release-v15\dbuild.15.0.dll

dbuild16:
#	cd msbuild\dbuild && devenv /Build "Release-v16|AnyCPU" /Project "dbuild" dbuild.sln
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v16;Platform=AnyCPU /t:Rebuild

dbuild16_1:
#	cd msbuild\dbuild && devenv /Build "Release-v16_1|AnyCPU" /Project "dbuild" dbuild.sln
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v16_1;Platform=AnyCPU /t:Rebuild

dbuild17:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17;Platform=AnyCPU /t:Rebuild

dbuild17_0:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_0;Platform=AnyCPU /t:Rebuild

dbuild17_1:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_1;Platform=AnyCPU /t:Rebuild

dbuild17_2:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_2;Platform=AnyCPU /t:Rebuild

dbuild17_3:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_3;Platform=AnyCPU /t:Rebuild

dbuild17_4:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_4;Platform=AnyCPU /t:Rebuild

dbuild17_5:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_5;Platform=AnyCPU /t:Rebuild

dbuild17_6:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_6;Platform=AnyCPU /t:Rebuild

dbuild17_7:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_7;Platform=AnyCPU /t:Rebuild

dbuild17_8:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_8;Platform=AnyCPU /t:Rebuild

dbuild17_9:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_9;Platform=AnyCPU /t:Rebuild

dbuild17_10:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_10;Platform=AnyCPU /t:Rebuild

dbuild17_11:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_11;Platform=AnyCPU /t:Rebuild

dbuild17_12:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_12;Platform=AnyCPU /t:Rebuild

dbuild17_13:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_13;Platform=AnyCPU /t:Rebuild

dbuild17_14:
	cd msbuild\dbuild && $(MSBUILD) dbuild.csproj /p:Configuration=Release-v17_14;Platform=AnyCPU /t:Rebuild

dbuild17_all: dbuild17_0 dbuild17_1 dbuild17_2 dbuild17_3 dbuild17_4 dbuild17_5 dbuild17_6 dbuild17_7 \
              dbuild17_8 dbuild17_9 dbuild17_10 dbuild17_11 dbuild17_12 dbuild17_13 dbuild17_14

mago:
	cd ..\..\mago && devenv /Build "Release|Win32" /Project "MagoNatDE" magodbg_2010.sln
	cd ..\..\mago && devenv /Build "Release|x64" /Project "MagoRemote" magodbg_2010.sln
	cd ..\..\mago && devenv /Build "Release StaticDE|Win32" /Project "MagoNatCC" magodbg_2010.sln

mago_vs15:
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141            /target:DebugEngine\MagoNatDE MagoDbg_2010.sln
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=x64;PlatformToolset=v141              /target:DebugEngine\MagoRemote MagoDbg_2010.sln
	cd ..\..\mago && msbuild "/p:Configuration=Release StaticDE;Platform=Win32;PlatformToolset=v141" /target:Expression\MagoNatCC MagoDbg_2010.sln

mago_vs16:
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v142            /target:DebugEngine\MagoNatDE MagoDbg_2010.sln
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=x64;PlatformToolset=v142              /target:DebugEngine\MagoRemote MagoDbg_2010.sln
	cd ..\..\mago && msbuild "/p:Configuration=Release StaticDE;Platform=Win32;PlatformToolset=v142" /target:Expression\MagoNatCC MagoDbg_2010.sln

mago_vs17:
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v143            /target:DebugEngine\MagoNatDE MagoDbg_2010.sln
	cd ..\..\mago && msbuild /p:Configuration=Release;Platform=x64;PlatformToolset=v143              /target:DebugEngine\MagoRemote MagoDbg_2010.sln
	cd ..\..\mago && msbuild "/p:Configuration=Release StaticDE;Platform=Win32;PlatformToolset=v143" /target:Expression\MagoNatCC MagoDbg_2010.sln

magocc_x64:
	cd ..\..\mago && msbuild "/p:Configuration=Release StaticDE;Platform=x64;PlatformToolset=v143" /target:Expression\MagoNatCC MagoDbg_2010.sln

magocc_arm64:
	cd ..\..\mago && msbuild "/p:Configuration=Release StaticDE;Platform=ARM64;PlatformToolset=v143" /target:Expression\MagoNatCC MagoDbg_2010.sln

magogc:
	cd ..\..\mago && devenv /Build "Release|Win32" /Project "MagoGC" magodbg_2010.sln
	cd ..\..\mago && devenv /Build "Release|x64" /Project "MagoGC" magodbg_2010.sln

magogc_ldc:
	cd ..\..\mago && devenv /Build "Release|Win32"/Project "MagoGC" /projectconfig "Release LDC|Win32" magodbg_2010.sln
	cd ..\..\mago && devenv /Build "Release|x64"  /Project "MagoGC" /projectconfig "Release LDC|x64"   magodbg_2010.sln

cv2pdb:
	cd ..\..\cv2pdb\trunk && devenv /Project "cv2pdb"      /Build "Release|Win32" src\cv2pdb_vs12.sln
	cd ..\..\cv2pdb\trunk && devenv /Project "dviewhelper" /Build "Release|Win32" src\cv2pdb_vs12.sln
	cd ..\..\cv2pdb\trunk && devenv /Project "dumplines"   /Build "Release|Win32" src\cv2pdb_vs12.sln

cv2pdb_vs15:
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141 src\cv2pdb.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141 src\dviewhelper\dviewhelper.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v141 src\dumplines.vcxproj

cv2pdb_vs16:
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v142 src\cv2pdb.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v142 src\dviewhelper\dviewhelper.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v142 src\dumplines.vcxproj

cv2pdb_vs17:
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v143 src\cv2pdb.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v143 src\dviewhelper\dviewhelper.vcxproj
	cd ..\..\cv2pdb\trunk && msbuild /p:Configuration=Release;Platform=Win32;PlatformToolset=v143 src\dumplines.vcxproj

dcxxfilt: $(DCXXFILT_EXE)
$(DCXXFILT_EXE): tools\dcxxfilt.d
# no space after Release, it will be part of environment variable
	cd tools && set CONFIG=Release&& build_dcxxfilt

##################################
# create installer

install_release_modules: install_modules fake_dparser cv2pdb_vs17 mago_vs17 magocc_x64 magocc_arm64 magogc magogc_ldc dbuild12 dbuild14 dbuild15

install_vs: install_release_modules install_only

install_vs_no_vs2017:   install_modules fake_dparser cv2pdb mago magogc dbuild12 dbuild14 fake_dbuild15 install_only

install_vs_only_vs2017: install_modules dparser dparser_test cv2pdb_vs15 mago_vs15 magogc fake_dbuild12 fake_dbuild14 dbuild15 install_only

install_modules: d_modules vdextension vdext15 visualdwizard dcxxfilt

d_modules: prerequisites visuald_vs visuald_vs_x64 visuald_vs_arm64 vdserver dmdserver

appveyor: d_modules cv2pdb_vs16 mago_vs16 magogc

install_only:
	if not exist ..\downloads\nul md ..\downloads
	cd nsis && "$(NSIS)\makensis" /V1 "/DCONFIG=$(CONFIG)" "/DCONFIG_DMDSERVER=$(CONFIG_DMDSERVER)" $(NSIS_ARGS) visuald.nsi
