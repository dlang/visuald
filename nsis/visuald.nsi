;NSIS Modern User Interface
;Welcome/Finish Page Example Script
;Written by Joost Verburg

;--------------------------------
;Include Modern UI

  !include "MUI2.nsh"
  !include "Memento.nsh"

;--------------------------------
;General

  !define VERSION "0.3.1"
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
  !define VS2005_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\8.0
  !define VS2008_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\9.0
  !define VS2010_REGISTRY_KEY     SOFTWARE\Microsoft\VisualStudio\10.0
  !define VCEXPRESS_REGISTRY_KEY  SOFTWARE\Microsoft\VCExpress\9.0

  ;Default installation folder
  InstallDir "$PROGRAMFILES\${APPNAME}"

  ;Get installation folder from registry if available
  InstallDirRegKey HKCU "Software\${APPNAME}" ""

  ;Request application privileges for Windows Vista
  RequestExecutionLevel user


;--------------------------------
;Interface Settings

  !define MUI_ABORTWARNING

;--------------------------------
;Pages

  !insertmacro MUI_PAGE_WELCOME
  !insertmacro MUI_PAGE_LICENSE "license"
  !insertmacro MUI_PAGE_COMPONENTS
  !insertmacro MUI_PAGE_DIRECTORY
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

  SetOutPath "$INSTDIR\Templates\Items"
  File ..\visuald\Templates\Items\empty.d
  File ..\visuald\Templates\Items\hello.d
  File ..\visuald\Templates\Items\items.vsdir

  SetOutPath "$INSTDIR\Templates\Projects\ConsoleApp"
  File ..\visuald\Templates\Projects\ConsoleApp\Program.d
  File ..\visuald\Templates\Projects\ConsoleApp\DLanguageApp.visualdproj
  File ..\visuald\Templates\Projects\ConsoleApp\ConsoleApp.vstemplate
  File ..\visuald\Templates\Projects\ConsoleApp\__TemplateIcon.ico

  SetOutPath "$INSTDIR\Templates\CodeSnippets"
  File ..\visuald\Templates\CodeSnippets\SnippetsIndex.xml
  
  SetOutPath "$INSTDIR\Templates\CodeSnippets\Snippets"
  File ..\visuald\Templates\CodeSnippets\Snippets\if.snippet
  File ..\visuald\Templates\CodeSnippets\Snippets\else.snippet
  File ..\visuald\Templates\CodeSnippets\Snippets\while.snippet
  File ..\visuald\Templates\CodeSnippets\Snippets\class.snippet
  File ..\visuald\Templates\CodeSnippets\Snippets\for.snippet

  ;Store installation folder
  WriteRegStr HKCU "Software\${APPNAME}" "" $INSTDIR
  
  ;Create uninstaller
  WriteRegStr ${UNINSTALL_REGISTRY_ROOT} "${UNINSTALL_REGISTRY_KEY}" "DisplayName" "${VERYLONG_APPNAME}"
  WriteRegStr ${UNINSTALL_REGISTRY_ROOT} "${UNINSTALL_REGISTRY_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
  
  WriteUninstaller "$INSTDIR\Uninstall.exe"
 
SectionEnd

;--------------------------------
${MementoSection} "Register with VS 2005" SecVS2005

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS2005_REGISTRY_KEY}'
  
${MementoSectionEnd}

;--------------------------------
${MementoSection} "Register with VS 2008" SecVS2008

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS2008_REGISTRY_KEY}'
  
${MementoSectionEnd}

;--------------------------------
${MementoSection} "Register with VS 2010" SecVS2010

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VS2010_REGISTRY_KEY}'
  
${MementoSectionEnd}

;--------------------------------
${MementoUnselectedSection} "Register with VC-Express" SecVCExpress

  ExecWait 'rundll32 "$INSTDIR\${DLLNAME}" RunDLLRegister ${VCEXPRESS_REGISTRY_KEY}'
  
${MementoSectionEnd}

${MementoSectionDone}

;--------------------------------
;Descriptions

  ;Language strings
  LangString DESC_SecPackage ${LANG_ENGLISH} "The package containing the language service."
  LangString DESC_SecVS2005 ${LANG_ENGLISH} "Register for usage in Visual Studio 2005."
  LangString DESC_SecVS2008 ${LANG_ENGLISH} "Register for usage in Visual Studio 2008."
  LangString DESC_SecVS2010 ${LANG_ENGLISH} "Register for usage in Visual Studio 2010."
  LangString DESC_SecVCExpress ${LANG_ENGLISH} "Register for usage in Visual C++ Express (experimental and unusable)."

  ;Assign language strings to sections
  !insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecPackage} $(DESC_SecPackage)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS2005} $(DESC_SecVS2005)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS2008} $(DESC_SecVS2008)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVS2010} $(DESC_SecVS2010)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecVCExpress} $(DESC_SecVCExpress)
  !insertmacro MUI_FUNCTION_DESCRIPTION_END


;--------------------------------
;Uninstaller Section

Section "Uninstall"

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
  DeleteRegKey /ifempty HKCU "Software\${APPNAME}"

SectionEnd

;--------------------------------
Function .onInstSuccess

  ${MementoSectionSave}

FunctionEnd

;--------------------------------
Function .onInit

  ${MementoSectionRestore}

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
  

FunctionEnd

