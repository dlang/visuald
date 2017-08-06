@echo off
rem expecting 
rem  - vsi2d.exe with path as the first argument
rem  - output file as second arg to remember build success
rem  - WindowsSdkDir to be set

set VSI2D=%~1
if "%VSI2D%" == "" (echo Error: please specify the path to vsi2d.exe as the first argument && exit /B 1)
if not exist "%VSI2D%" (echo %1 does not exist && exit /B 1)

set OUT=%~2
if "%OUT%" == "" (echo Error: please specify the output path to remember succesful builds as second argument && exit /B 1)
if exist "%OUT%" del "%OUT%"

if not exist ..\sdk\lib\nul     md ..\sdk\lib

set LIBS=kernel32.lib user32.lib winspool.lib advapi32.lib
set LIBS=%LIBS% comdlg32.lib gdi32.lib ole32.lib rpcrt4.lib shell32.lib winmm.lib
set LIBS=%LIBS% wsock32.lib comctl32.lib oleaut32.lib ws2_32.lib odbc32.lib

echo WindowsSdkDir=%WindowsSdkDir%
set WINSDKLIB=
if "%WINSDKLIB%" == "" if exist "%WindowsSdkDir%\lib\%WindowsSDKLibVersion%\um\x86\kernel32.lib" set WINSDKLIB=%WindowsSdkDir%\lib\%WindowsSDKLibVersion%\um\x86
if "%WINSDKLIB%" == "" if exist "%WindowsSdkDir%\lib\%WindowsSDKVersion%\um\x86\kernel32.lib" set WINSDKLIB=%WindowsSdkDir%\lib\%WindowsLibVersion%\um\x86
if "%WINSDKLIB%" == "" if exist "%WindowsSdkDir%\lib\winv6.3\um\x86\kernel32.lib" set WINSDKLIB=%WindowsSdkDir%\lib\winv6.3\um\x86
if "%WINSDKLIB%" == "" if exist "%WindowsSdkDir%\lib\win8\um\x86\kernel32.lib" set WINSDKLIB=%WindowsSdkDir%\lib\win8\um\x86
if "%WINSDKLIB%" == "" if exist "%WindowsSdkDir%\lib\kernel32.lib" set WINSDKLIB=%WindowsSdkDir%\lib
if "%WINSDKLIB%" == "" (echo Error: could not detect the Windows SDK library folder && exit /B 1)

set COFFIMPLIB=c:\l\dmc\bin\coffimplib.exe
if not exist %COFFIMPLIB% set COFFIMPLIB=%DMDInstallDir%\windows\bin\coffimplib.exe
if not exist %COFFIMPLIB% set COFFIMPLIB=coffimplib
%coffimplib% >nul 2>&1
if errorlevel 9000 (echo Error: cannot execute %COFFIMPLIB%, please add to PATH && exit /B 1)

for %%f in (%LIBS%) do (
	%COFFIMPLIB% "%WINSDKLIB%\%%f" ..\sdk\lib\%%f 
	if errorlevel 1 exit /B 1
)

echo Success > "%OUT%"
exit /B 0
