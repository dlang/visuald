set DMD=m:\s\d\rainers\windows\bin\dmd.exe
set WEB=m:\s\d\rainers\web\visuald

set SRC=ReportingBugs.dd
set SRC=%SRC% StartPage.dd
set SRC=%SRC% ReportingBugs.dd
set SRC=%SRC% BuildFromSource.dd
set SRC=%SRC% KnownIssues.dd
set SRC=%SRC% Installation.dd
set SRC=%SRC% BrowseInfo.dd
set SRC=%SRC% Profiling.dd
set SRC=%SRC% CppConversion.dd
set SRC=%SRC% Debugging.dd
set SRC=%SRC% ProjectConfig.dd
set SRC=%SRC% TokenReplace.dd
set SRC=%SRC% Search.dd
set SRC=%SRC% Editor.dd
set SRC=%SRC% ProjectWizard.dd
set SRC=%SRC% GlobalOptions.dd
set SRC=%SRC% Features.dd
set SRC=%SRC% VersionHistory.dd

set DDOC=macros.ddoc html.ddoc visuald.ddoc

if not exist %WEB% md %WEB%
if not exist %WEB%\images md %WEB%\images
cp -u images/* %WEB%\images
%DMD% -Dd%WEB% -o- -w %DDOC% %SRC%

