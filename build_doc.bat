setlocal
set DMD=c:\s\d\rainers\windows\bin\dmd.exe
rem set WEB=m:\s\d\rainers\web\visuald
set WEB=c:\s\d\visuald\gh-pages\visuald
set CP=c:\u\gnuwin\cp.exe

set SRC=      doc/ReportingBugs.dd
set SRC=%SRC% doc/StartPage.dd
set SRC=%SRC% doc/ReportingBugs.dd
set SRC=%SRC% doc/BuildFromSource.dd
set SRC=%SRC% doc/KnownIssues.dd
set SRC=%SRC% doc/Installation.dd
set SRC=%SRC% doc/BrowseInfo.dd
set SRC=%SRC% doc/Profiling.dd
set SRC=%SRC% doc/Coverage.dd
set SRC=%SRC% doc/CppConversion.dd
set SRC=%SRC% doc/Debugging.dd
set SRC=%SRC% doc/ProjectConfig.dd
set SRC=%SRC% doc/TokenReplace.dd
set SRC=%SRC% doc/Search.dd
set SRC=%SRC% doc/Editor.dd
set SRC=%SRC% doc/ProjectWizard.dd
set SRC=%SRC% doc/GlobalOptions.dd
set SRC=%SRC% doc/Features.dd
set SRC=%SRC% doc/VersionHistory.dd
set SRC=%SRC% doc/News36.dd
set SRC=%SRC% doc/CompileCommands.dd
set SRC=%SRC% doc/DustMite.dd
set SRC=%SRC% doc/vcxproject.dd

set DDOC=doc/macros.ddoc doc/html.ddoc doc/dlang.org.ddoc doc/visuald.ddoc
rem ..\..\rainers\d-programming-language.org\dlang.org.ddoc

if not exist %WEB% md %WEB%
if not exist %WEB%\images md %WEB%\images
%cp% -u doc/images/* %WEB%\images

if not exist %WEB%\css md %WEB%\css
%cp% -u doc/css/* %WEB%\css

if not exist %WEB%\js md %WEB%\js
%cp% -u doc/js/* %WEB%\js

%cp% -u doc/favicon.ico %WEB%

%DMD% -Dd%WEB% -o- -w %DDOC% %SRC%

