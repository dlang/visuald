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

if "%WindowsSdkDir%" == "" (echo Error: environment variable WindowsSdkDir not set && exit /B 1)

set DTE_IDL_PATH=..\sdk\vsi\idl
if not exist ..\sdk\vsi\nul     md ..\sdk\vsi
if not exist ..\sdk\win32\nul   md ..\sdk\win32
if not exist %DTE_IDL_PATH%\nul md %DTE_IDL_PATH%

if "%WindowsSDKVersion%" == "\" set WindowsSDKVersion=%UCRTVersion%
if "%WindowsSDKVersion%" == "" set WindowsSDKVersion=%UCRTVersion%
set WINSDKINC=
if not "%WindowsSDKVersion%" == "" if exist "%WindowsSdkDir%\include\%WindowsSDKVersion%\um\windows.h" set WINSDKINC=%WindowsSdkDir%\include\%WindowsSDKVersion%
if "%WINSDKINC%" == "" set WINSDKINC=%WindowsSdkDir%\include
if not exist "%WINSDKINC%\windows.h" if not exist "%WINSDKINC%\um\windows.h" (echo Error: could not detect the Windows SDK && exit /B 1)

set VSISDKINC=
if "%VSISDKINC%" == "" if not "%VSSDK150Install%" == "" set VSISDKINC=%VSSDK150Install%
if "%VSISDKINC%" == "" if not "%VSSDK140Install%" == "" set VSISDKINC=%VSSDK140Install%
if "%VSISDKINC%" == "" if not "%VSSDK120Install%" == "" set VSISDKINC=%VSSDK120Install%
if "%VSISDKINC%" == "" if not "%VSSDK110Install%" == "" set VSISDKINC=%VSSDK110Install%
if "%VSISDKINC%" == "" if not "%VSSDK100Install%" == "" set VSISDKINC=%VSSDK100Install%
if "%VSISDKINC%" == "" if not "%VSSDK90Install%" == "" set VSISDKINC=%VSSDK90Install%
if "%VSISDKINC%" == "" if not "%VSSDK80Install%" == "" set VSISDKINC=%VSSDK80Install%
if "%VSISDKINC%" == "" (echo Error: could not detect the Visual Studio SDK && exit /B 1)

if not exist "%VSISDKINC%\VisualStudioIntegration\Common\Inc\textmgr.h" (echo unexpected Visual Studio SDK installation at "%VSISDKINC%" && exit /B 1)

echo Translating Windows SDK and Visual Studio SDK to D, this can take several minutes. Please be patient.
echo "%VSI2D%" --vsi="%VSISDKINC:\=/%" --win="%WINSDKINC:\=/%" --dte="%DTE_IDL_PATH%" --sdk=..\sdk
"%VSI2D%" --vsi="%VSISDKINC:\=/%" --win="%WINSDKINC:\=/%" --dte="%DTE_IDL_PATH%" --sdk=..\sdk
if errorlevel 1 exit /B 1

echo Translation successful! 
echo Visual Studio now prompts to reload the vsi project, but cannot do so because the build is still running.
echo Please reload the solution manually.
echo Success > "%OUT%"
exit /B 0
