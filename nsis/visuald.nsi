;VisualD installation script

;--------------------------------
;Include Modern UI

  !include "MUI2.nsh"
  !include "Memento.nsh"
  !include "InstallOptions.nsh"

;--------------------------------
;General
  !searchparse /file ../version "#define VERSION_MAJOR " VERSION_MAJOR
  !searchparse /file ../version "#define VERSION_MINOR " VERSION_MINOR
  !searchparse /file ../version "#define VERSION_REVISION " VERSION_REVISION

  !searchreplace VERSION_MAJOR ${VERSION_MAJOR} " " ""
  !searchreplace VERSION_MINOR ${VERSION_MINOR} " " ""
  !searchreplace VERSION_REVISION ${VERSION_REVISION} " " ""
  
  !define VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_REVISION}"
  !echo "VERSION = ${VERSION}"
  !define APPNAME "VisualD"
  !define LONG_APPNAME "Visual D"
  !define VERYLONG_APPNAME "Visual D - Visual Studio Integration of the D Programming Language"

  !define DLLNAME "visuald.dll"
  !define CONFIG  "Release"

  ;Name and file
  Name "${LONG_APPNAME}"
  OutFile "..\..\downloads\${APPNAME}-v${VERSION}.exe"

  !define UNINSTALL_REGISTRY_ROOT HKLM
  !define UNINSTALL_REGISTRY_KEY  Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}

  !define MEMENTO_REGISTRY_ROOT   ${UNINSTALL_REGISTRY_ROOT}
  !define MEMENTO_REGISTRY_KEY    ${UNINSTALL_REGISTRY_KEY}
  
  !define VS_REGISTRY_ROOT        HKLM
  !define VS_NET_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\7.1
  !define VS2005_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\8.0
  !define VS2008_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\9.0
  !define VS2010_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\10.0
  !define VCEXPRESS_REGISTRY_KEY  SOFTWARE\Microsoft\VCExpress\9.0
  !define VDSETTINGS_KEY          "\ToolsOptionsPages\Projects\Visual D Settings"
  
  ;Default installation folder
  InstallDir "$PROGRAMFILES\${APPNAME}"

  ;Get installation folder from registry if available
  InstallDirRegKey HKCU "Software\${APPNAME}" ""

  ;Request application privileges for Windows Vista
  RequestExecutionLevel user

  ReserveFile "dmdinstall.ini"

;--------------------------------
;installation time variables
  Var DMDInstallDir

;--------------------------------
;Interface Settings

  !define MUI_ABORTWARNING

;--------------------------------
;Pages

  !insertmacro MUI_PAGE_WELCOME
  !insertmacro MUI_PAGE_LICENSE "license"
  !insertmacro MUI_PAGE_COMPONENTS
  !insertmacro MUI_PAGE_DIRECTORY

  Page custom DMDInstallPage ValidateDMDInstallPage
  
  !insertmacro MUI_PAGE_INSTFILES
  !insertmacro MUI_PAGE_FINISH

  !insertmacro MUI_UNPAGE_WELCOME
  !insertmacro MUI_UNPAGE_CONFIRM
  !insertmacro MUI_UNPAGE_INSTFILES
  !insertmacro MUI_UNPAGE_FINISH

;--------------------------------
;Languages

  !insertmacro MUI_LANGUAGE "English"

;--------------------------------
;Installer Section

Section "Visual Studio package" SecPackage

  SectionIn RO
  SetOutPath "$INSTDIR"
  
  ;ADD YOUR OWN FILES HERE...
  File ..\bin\${CONFIG}\${DLLNAME}
  File ..\README
  File ..\LICENSE
  File ..\CHANGES

  SetOutPath "$INSTDIR\Templates\Items"
  File ..\visuald\Templates\Items\empty.d
  File ..\visuald\Templates\Items\hello.d
  File ..\visuald\Templates\Items\items.vsdir

  SetOutPath "$INSTDIR\Templates\ProjectItems\ConsoleApp"
  File ..\visuald\Templates\ProjectItems\ConsoleApp\main.d
  File ..\visuald\Templates\ProjectItems\ConsoleApp\ConsoleApp.vstemplate
  File ..\visuald\Templates\ProjectItems\ConsoleApp\ConsoleApp.visualdproj

  SetOutPath "$INSTDIR\Templates\ProjectItems\WindowsApp"
  File ..\visuald\Templates\ProjectItems\WindowsApp\winmain.d
  File ..\visuald\Templates\ProjectItems\WindowsApp\WindowsApp.vstemplate
  File ..\visuald\Templates\ProjectItems\WindowsApp\WindowsApp.visualdproj

  SetOutPath "$INSTDIR\Templates\ProjectItems\DynamicLib"
  File ..\visuald\Templates\ProjectItems\DynamicLib\dllmain.d
  File ..\visuald\Templates\ProjectItems\DynamicLib\DynamicLib.vstemplate
  File ..\visuald\Templates\ProjectItems\DynamicLib\DynamicLib.visualdproj

  SetOutPath "$INSTDIR\Templates\ProjectItems\StaticLib"
  File ..\visuald\Templates\ProjectItems\StaticLib\lib.d
  File ..\visuald\Templates\ProjectItems\StaticLib\StaticLib.vstemplate
  File ..\visuald\Templates\ProjectItems\StaticLib\StaticLib.visualdproj

  SetOutPath "$INSTDIR\Templates\ProjectItems\Projects"
  File ..\visuald\Templates\Projects\DTemplates.vsdir

  SetOutPath "$INSTDIR\Templates\CodeSnippets"
  File ..\visuald\Templates\CodeSnippets\SnippetsIndex.xml
  
  SetOutPath "$INSTDIR\Templates\CodeSnippets\Snippets"
  File ..\visuald\Templates\CodeSnippets\Snippets\*.snippet

  ;Store installation folder
  WriteRegStr HKCU "Software\${APPNAME}" "" $INSTDIR

  ;Create uninstaller
  WriteRegStr ${UNINSTALL_REGISTRY_ROOT} "${UNINSTALL_REGISTRY_KEY}" "DisplayName" "${VERYLONG_APPNAME}"
  WriteRegStr ${UNINSTALL_REGISTRY_ROOT} "${UNINSTALL_REGISTRY_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
  
  WriteUninstaller "$INSTDIR\Uninstall.exe"
 
SectionEnd

;--------------------------------
${MementoSection} "Register with VS.NET" SecVS_NET

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS_NET_REGISTRY_KEY}'
  WriteRegStr ${VS_REGISTRY_ROOT} "${VS_NET_REGISTRY_KEY}${VDSETTINGS_KEY}" "DMDInstallDir" $DMDInstallDir
  
${MementoSectionEnd}

;--------------------------------
${MementoSection} "Register with VS 2005" SecVS2005

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS2005_REGISTRY_KEY}'
  WriteRegStr ${VS_REGISTRY_ROOT} "${VS2005_REGISTRY_KEY}${VDSETTINGS_KEY}" "DMDInstallDir" $DMDInstallDir
  
${MementoSectionEnd}

;--------------------------------
${MementoSection} "Register with VS 2008" SecVS2008

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS2008_REGISTRY_KEY}'
  WriteRegStr ${VS_REGISTRY_ROOT} "${VS2008_REGISTRY_KEY}${VDSETTINGS_KEY}" "DMDInstallDir" $DMDInstallDir 
  
${MementoSectionEnd}

;--------------------------------
${MementoSection} "Register with VS 2010" SecVS2010

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS2010_REGISTRY_KEY}'
  WriteRegStr ${VS_REGISTRY_ROOT} "${VS2010_REGISTRY_KEY}${VDSETTINGS_KEY}" "DMDInstallDir" $DMDInstallDir
  
${MementoSectionEnd}

;--------------------------------
${MementoUnselectedSection} "Register with VC-Express" SecVCExpress

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VCEXPRESS_REGISTRY_KEY}'
  WriteRegStr ${VS_REGISTRY_ROOT} "${VCEXPRESS_REGISTRY_KEY}${VDSETTINGS_KEY}" "DMDInstallDir" $DMDInstallDir
  
${MementoSectionEnd}

${MementoSectionDone}

;--------------------------------
;Descriptions

  ;Language strings
  LangString DESC_SecPackage ${LANG_ENGLISH} "The package containing the language service."
  LangString DESC_SecVS_NET ${LANG_ENGLISH} "Register for usage in Visual Studio .NET"
  LangString DESC_SecVS2005 ${LANG_ENGLISH} "Register for usage in Visual Studio 2005."
  LangString DESC_SecVS2008 ${LANG_ENGLISH} "Register for usage in Visual Studio 2008."
  LangString DESC_SecVS2010 ${LANG_ENGLISH} "Register for usage in Visual Studio 2010."
  LangString DESC_SecVCExpress ${LANG_ENGLISH} "Register for usage in Visual C++ Express (experimental and unusable)."

  ;Assign language strings to sections
  !insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecPackage} $(DESC_SecPackage)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS_NET} $(DESC_SecVS_NET)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS2005} $(DESC_SecVS2005)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS2008} $(DESC_SecVS2008)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS2010} $(DESC_SecVS2010)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVCExpress} $(DESC_SecVCExpress)
  !insertmacro MUI_FUNCTION_DESCRIPTION_END


;--------------------------------
;Uninstaller Section

Section "Uninstall"

  ExecWait 'rundll32 $INSTDIR\${DLLNAME} RunDLLUnregister ${VS_NET_REGISTRY_KEY}'
  ExecWait 'rundll32 $INSTDIR\${DLLNAME} RunDLLUnregister ${VS2005_REGISTRY_KEY}'
  ExecWait 'rundll32 $INSTDIR\${DLLNAME} RunDLLUnregister ${VS2008_REGISTRY_KEY}'
  ExecWait 'rundll32 $INSTDIR\${DLLNAME} RunDLLUnregister ${VS2010_REGISTRY_KEY}'
  ExecWait 'rundll32 $INSTDIR\${DLLNAME} RunDLLUnregister ${VCEXPRESS_REGISTRY_KEY}'

  ;ADD YOUR OWN FILES HERE...
  Delete "$INSTDIR\${DLLNAME}"
  Delete "$INSTDIR\Uninstall.exe"

  RMDir "$INSTDIR"

  DeleteRegKey ${UNINSTALL_REGISTRY_ROOT} "${UNINSTALL_REGISTRY_KEY}"
  DeleteRegKey HKLM "SOFTWARE\${APPNAME}"
  DeleteRegKey HKCU "Software\${APPNAME}"
  ; /ifempty 

SectionEnd

;--------------------------------
Function .onInstSuccess

  ${MementoSectionSave}

FunctionEnd

;--------------------------------
Function .onInit

  ${MementoSectionRestore}

  ; detect VS.NET
  ClearErrors
  ReadRegStr $1 ${VS_REGISTRY_ROOT} "${VS_NET_REGISTRY_KEY}" InstallDir
  IfErrors 0 Installed_VS_NET
    SectionSetFlags ${SecVS_NET} ${SF_RO}
  Installed_VS_NET:
  
  ; detect VS2005
  ClearErrors
  ReadRegStr $1 ${VS_REGISTRY_ROOT} "${VS2005_REGISTRY_KEY}" InstallDir
  IfErrors 0 Installed_VS2005
    SectionSetFlags ${SecVS2005} ${SF_RO}
  Installed_VS2005:
  
  ; detect VS2008
  ClearErrors
  ReadRegStr $1 ${VS_REGISTRY_ROOT} "${VS2008_REGISTRY_KEY}" InstallDir
  IfErrors 0 Installed_VS2008
    SectionSetFlags ${SecVS2008} ${SF_RO}
  Installed_VS2008:

  ; detect VS2010
  ClearErrors
  ReadRegStr $1 ${VS_REGISTRY_ROOT} "${VS2010_REGISTRY_KEY}" InstallDir
  IfErrors 0 Installed_VS2010
    SectionSetFlags ${SecVS2010} ${SF_RO}
  Installed_VS2010:

  ; detect VCExpress
  ClearErrors
  ReadRegStr $1 ${VS_REGISTRY_ROOT} "${VCEXPRESS_REGISTRY_KEY}" InstallDir
  IfErrors 0 Installed_VCExpress
    SectionSetFlags ${SecVcExpress} ${SF_RO}
  Installed_VCExpress:

  !insertmacro INSTALLOPTIONS_EXTRACT "dmdinstall.ini"
  
FunctionEnd

;--------------------------------
Function DMDInstallPage

  !insertmacro MUI_HEADER_TEXT "DMD Installation Folder" "Specify the directory where DMD is installed"

  ReadRegStr $DMDInstallDir HKLM "Software\${APPNAME}" "DMDInstallDir" 
  
  WriteINIStr "$PLUGINSDIR\dmdinstall.ini" "Field 1" "State" $DMDInstallDir
  !insertmacro INSTALLOPTIONS_DISPLAY "dmdinstall.ini"
  
FunctionEnd

Function ValidateDMDInstallPage
  ReadINIStr $DMDInstallDir "$PLUGINSDIR\dmdinstall.ini" "Field 1" "State"
  WriteRegStr HKLM "Software\${APPNAME}" "DMDInstallDir" $DMDInstallDir
FunctionEnd
