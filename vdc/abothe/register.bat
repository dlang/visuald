rem run this batch once after compilation to register the debug version
rem regasm must be in the PATH, so you could just use the VS2010 command line

rem Framework 4+ needed
set regasm=c:\Windows\Microsoft.NET\Framework\v4.0.30319\RegAsm.exe 

%regasm% ..\..\bin\Debug\abothe.VDServer.dll /codebase /regfile:%cd%\abothe.vdserver.reg
if errorlevel 1 goto xit

rem for 64-bit OS, we must add these entries into the Wow6432Node hive of the registry
if not exist c:\windows\syswow64\regedit.exe goto win32

c:\windows\syswow64\regedit -m %cd%\abothe.vdserver.reg
goto xit

:win32
regedit -m %cd%\abothe.vdserver.reg

:xit