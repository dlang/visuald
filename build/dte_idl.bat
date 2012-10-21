@echo off
rem expecting 
rem  - tlb2idl.exe with path as the first argument
rem  - output file as second arg to remember build success
rem  - WindowsSdkDir to be set

if "%1" == "" (echo please specify the path to tlb2idl.exe as the first argument && exit /B 1)
set TLB2IDL=%1
if not exist "%TLB2IDL%" (echo %1 does not exist && exit /B 1)

if "%2" == "" (echo please specify the output path to remember succesful builds as second argument && exit /B 1)
set OUT=%2
if exist %OUT% del %OUT%

set DTE_IDL_PATH=..\sdk\vsi\idl
if not exist ..\sdk\vsi\nul     md ..\sdk\vsi
if not exist %DTE_IDL_PATH%\nul md %DTE_IDL_PATH%

set MSENV=%COMMONPROGRAMFILES%\Microsoft Shared\MSEnv
if not exist "%MSENV%\dte80.olb" (echo "%MSENV%\dte80.olb" does not exist && exit /B 1)

set IVIEWER=
if "%IVIEWER%" == "" if exist "%WindowsSdkDir%\bin\x86\iviewers.dll" set IVIEWER=%WindowsSdkDir%\bin\x86\iviewers.dll
if "%IVIEWER%" == "" if exist "%WindowsSdkDir%\bin\iviewers.dll"     set IVIEWER=%WindowsSdkDir%\bin\iviewers.dll
if "%IVIEWER%" == "" (echo "iviewer.dll" not found && exit /B 1)

echo %TLB2IDL% "%MSENV%\dte80.olb" "%DTE_IDL_PATH%\dte80.idl" "%IVIEWER%"

%TLB2IDL% "%MSENV%\dte80.olb" "%DTE_IDL_PATH%\dte80.idl" "%IVIEWER%"
if errorlevel 1 exit /B 1
%TLB2IDL% "%MSENV%\dte80a.olb" "%DTE_IDL_PATH%\dte80a.idl" "%IVIEWER%"
if errorlevel 1 exit /B 1
%TLB2IDL% "%MSENV%\dte90.olb" "%DTE_IDL_PATH%\dte90.idl" "%IVIEWER%"
if errorlevel 1 exit /B 1
echo Success > %OUT%
exit /B 0
