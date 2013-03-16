//
// Written and provided by Benjamin Thaut
// Complications improved by Rainer Schuetze
//
// file access monitoring added by Rainer Schuetze, needs filemonitor.dll in the same 
//  directory as pipedmd.exe

module main;

import std.stdio;
import std.c.windows.windows;
import std.windows.charset;
import core.stdc.string;
import std.string;
import std.regex;
import core.demangle;
import std.array;
import std.algorithm;
import std.conv;
import std.path;

extern(C)
{
  struct PROCESS_INFORMATION {
    HANDLE hProcess;
    HANDLE hThread;
    DWORD dwProcessId;
    DWORD dwThreadId;
  }

  alias PROCESS_INFORMATION* LPPROCESS_INFORMATION;

  struct STARTUPINFOA {
    DWORD   cb;
    LPSTR   lpReserved;
    LPSTR   lpDesktop;
    LPSTR   lpTitle;
    DWORD   dwX;
    DWORD   dwY;
    DWORD   dwXSize;
    DWORD   dwYSize;
    DWORD   dwXCountChars;
    DWORD   dwYCountChars;
    DWORD   dwFillAttribute;
    DWORD   dwFlags;
    WORD    wShowWindow;
    WORD    cbReserved2;
    LPBYTE  lpReserved2;
    HANDLE  hStdInput;
    HANDLE  hStdOutput;
    HANDLE  hStdError;
  }

  alias STARTUPINFOA* LPSTARTUPINFOA;
}

extern(System)
{
  BOOL CreatePipe(
               HANDLE* hReadPipe,
               HANDLE* hWritePipe,
               SECURITY_ATTRIBUTES* lpPipeAttributes,
               DWORD nSize
               );

  BOOL SetHandleInformation(
                         HANDLE hObject,
                         DWORD dwMask,
                         DWORD dwFlags
                         );

  BOOL
    CreateProcessA(
                   LPCSTR lpApplicationName,
                   LPSTR lpCommandLine,
                   LPSECURITY_ATTRIBUTES lpProcessAttributes,
                   LPSECURITY_ATTRIBUTES lpThreadAttributes,
                   BOOL bInheritHandles,
                   DWORD dwCreationFlags,
                   LPVOID lpEnvironment,
                   LPCSTR lpCurrentDirectory,
                   LPSTARTUPINFOA lpStartupInfo,
                   LPPROCESS_INFORMATION lpProcessInformation
                   );

  BOOL
    GetExitCodeProcess(
                       HANDLE hProcess,
                       LPDWORD lpExitCode
                       );

  BOOL
    PeekNamedPipe(
                  HANDLE hNamedPipe,
                  LPVOID lpBuffer,
                  DWORD nBufferSize,
                  LPDWORD lpBytesRead,
                  LPDWORD lpTotalBytesAvail,
                  LPDWORD lpBytesLeftThisMessage
                  );

  UINT GetKBCodePage();
}

enum uint HANDLE_FLAG_INHERIT = 0x00000001;
enum uint HANDLE_FLAG_PROTECT_FROM_CLOSE = 0x00000002;

enum uint STARTF_USESHOWWINDOW  =  0x00000001;
enum uint STARTF_USESIZE        =  0x00000002;
enum uint STARTF_USEPOSITION    =  0x00000004;
enum uint STARTF_USECOUNTCHARS  =  0x00000008;
enum uint STARTF_USEFILLATTRIBUTE = 0x00000010;
enum uint STARTF_RUNFULLSCREEN   = 0x00000020;  // ignored for non-x86 platforms
enum uint STARTF_FORCEONFEEDBACK = 0x00000040;
enum uint STARTF_FORCEOFFFEEDBACK = 0x00000080;
enum uint STARTF_USESTDHANDLES   = 0x00000100;

enum uint CREATE_SUSPENDED = 0x00000004;

alias std.c.stdio.stdout stdout;

static bool isIdentifierChar(char ch)
{
  // include C++,Pascal,Windows mangling and UTF8 encoding and compression 
  return ch >= 0x80 || (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
}

static bool isDigit(char ch)
{
  return (ch >= '0' && ch <= '9');
}

int main(string[] argv)
{
  if(argv.length < 2)
  {
    printf("pipedmd V0.2, written 2012 by Benjamin Thaut, complications improved by Rainer Schuetze\n");
    printf("decompresses and demangles names in OPTLINK and ld messages\n");
    printf("\n");
    printf("usage: %s [-nodemangle] [-gdcmode] [-deps depfile] [executable] [arguments]\n", argv[0].ptr);
    return -1;
  }
  int skipargs;
  string depsfile;
  bool doDemangle = true;
  bool gdcMode = false;
  if(argv.length >= 2 && argv[1] == "-nodemangle")
  {
    doDemangle = false;
    skipargs = 1;
  }
  if(argv.length >= skipargs + 2 && argv[skipargs + 1] == "-gdcmode")
  {
    gdcMode = true;
    skipargs++;
  }
  if(argv.length > skipargs + 2 && argv[skipargs + 1] == "-deps")
    depsfile = argv[skipargs += 2];
  
  string command; //= "gdc";
  for(int i = skipargs + 1;i < argv.length; i++)
  {
    if(command.length > 0)
      command ~= " ";
    if(countUntil(argv[i], ' ') < argv[i].length)
      command ~= "\"" ~ argv[i] ~ "\"";
    else
      command ~= argv[i];
  }

  HANDLE hStdOutRead;
  HANDLE hStdOutWrite;
  HANDLE hStdInRead;
  HANDLE hStdInWrite;

  SECURITY_ATTRIBUTES saAttr; 

  // Set the bInheritHandle flag so pipe handles are inherited. 

  saAttr.nLength = SECURITY_ATTRIBUTES.sizeof;
  saAttr.bInheritHandle = TRUE; 
  saAttr.lpSecurityDescriptor = null; 

  // Create a pipe for the child process's STDOUT. 

  if ( ! CreatePipe(&hStdOutRead, &hStdOutWrite, &saAttr, 0) ) 
    assert(0);

  // Ensure the read handle to the pipe for STDOUT is not inherited.

  if ( ! SetHandleInformation(hStdOutRead, HANDLE_FLAG_INHERIT, 0) )
    assert(0);

  if ( ! CreatePipe(&hStdInRead, &hStdInWrite, &saAttr, 0) )
    assert(0);

  if ( ! SetHandleInformation(hStdInWrite, HANDLE_FLAG_INHERIT, 0) )
    assert(0);

  PROCESS_INFORMATION piProcInfo; 
  STARTUPINFOA siStartInfo;
  BOOL bSuccess = FALSE; 

  // Set up members of the PROCESS_INFORMATION structure. 

  memset( &piProcInfo, 0, PROCESS_INFORMATION.sizeof );

  // Set up members of the STARTUPINFO structure. 
  // This structure specifies the STDIN and STDOUT handles for redirection.

  memset( &siStartInfo, 0, STARTUPINFOA.sizeof );
  siStartInfo.cb = STARTUPINFOA.sizeof; 
  siStartInfo.hStdError = hStdOutWrite;
  siStartInfo.hStdOutput = hStdOutWrite;
  siStartInfo.hStdInput = hStdInRead;
  siStartInfo.dwFlags |= STARTF_USESTDHANDLES;

  int cp = GetKBCodePage();
  auto szCommand = toMBSz(command, cp);
  bSuccess = CreateProcessA(null, 
                            cast(char*)szCommand,     // command line 
                            null,          // process security attributes 
                            null,          // primary thread security attributes 
                            TRUE,          // handles are inherited 
                            CREATE_SUSPENDED,             // creation flags 
                            null,          // use parent's environment 
                            null,          // use parent's current directory 
                            &siStartInfo,  // STARTUPINFO pointer 
                            &piProcInfo);  // receives PROCESS_INFORMATION 

  if(!bSuccess)
  {
    printf("failed launching %s\n", szCommand);
    return 1;
  }

  if(depsfile.length)
    InjectDLL(piProcInfo.hProcess, depsfile);
  ResumeThread(piProcInfo.hThread);

  char[] buffer = new char[2048];
  DWORD bytesRead = 0;
  DWORD bytesAvaiable = 0;
  DWORD exitCode = 0;
  bool linkerFound = gdcMode;

  while(true)
  {
    bSuccess = PeekNamedPipe(hStdOutRead, buffer.ptr, buffer.length, &bytesRead, &bytesAvaiable, null);
    if(bSuccess && bytesAvaiable > 0)
    {
      size_t lineLength = 0;
      for(; lineLength < buffer.length && lineLength < bytesAvaiable && buffer[lineLength] != '\n'; lineLength++){}
      if(lineLength >= bytesAvaiable)
      {
        // if no line end found, retry with larger buffer
        if(lineLength >= buffer.length)
          buffer.length = buffer.length * 2;
        continue;
      }
      bSuccess = ReadFile(hStdOutRead, buffer.ptr, lineLength+1, &bytesRead, null);
      if(!bSuccess || bytesRead == 0)
        break;

      bytesRead--; //remove \n
      while(bytesRead > 0 && buffer[bytesRead-1] == '\r') // remove \r
        bytesRead--; 
      DWORD skip = 0;
      while(skip < bytesRead && buffer[skip] == '\r') // remove \r
        skip++;

      char[] output = buffer[skip..bytesRead];
      size_t writepos = 0;

      if(!linkerFound && output.startsWith("OPTLINK (R)"))
        linkerFound = true;

      if(doDemangle && linkerFound)
      {
        if(gdcMode)
        {
            if(output.countUntil("undefined reference to") >= 0 || output.countUntil("In function") >= 0)
            {
                auto startIndex = output.lastIndexOf('`');
                auto endIndex = output.lastIndexOf('\'');
                if(startIndex >= 0 && startIndex < endIndex)
                {
                    auto symbolName = output[startIndex+1..endIndex];
                    if(symbolName.length > 2 && symbolName[0] == '_' && symbolName[1] == 'D')
                    {
                        auto demangeledSymbolName = demangle(symbolName);
                        if(demangeledSymbolName != symbolName)
                        {
                            fwrite(output.ptr, endIndex+1, 1, stdout);
                            writepos = endIndex+1;
                            fwrite(" (".ptr, 2, 1, stdout);
                            fwrite(demangeledSymbolName.ptr, demangeledSymbolName.length, 1, stdout);
                            fwrite(")".ptr, 1, 1, stdout);
                        }
                    }
                }
            }
        }
        else
        {
            for(int p = 0; p < output.length; p++)
              if(isIdentifierChar(output[p]))
              {
                int q = p;
                while(p < output.length && isIdentifierChar(output[p]))
                  p++;

                auto symbolName = output[q..p];
                size_t pos = 0;
                const(char)[] realSymbolName = decodeDmdString(symbolName, pos);
                if(pos != p - q)
                {
                    // could not decode, might contain UTF8 elements, so try translating to the current code page
                    // (demangling will not work anyway)
                    try
                    {
                      auto szName = toMBSz(symbolName, cp);
                      auto plen = strlen(szName);
                      realSymbolName = szName[0..plen];
                      pos = p - q;
                    }
                    catch(Exception)
                    {
                    }
                }
                if(pos == p - q)
                {
                  if(realSymbolName != symbolName)
                  {
                    // not sure if output is UTF8 encoded, so avoid any translation
                    if(q > writepos)
                      fwrite(output.ptr + writepos, q - writepos, 1, stdout);
                    fwrite(realSymbolName.ptr, realSymbolName.length, 1, stdout);
                    writepos = p;
                  }
                  while(realSymbolName.length > 1 && realSymbolName[0] == '_')
                      realSymbolName = realSymbolName[1..$];
                  if(realSymbolName.length > 2 && realSymbolName[0] == 'D' && isDigit(realSymbolName[1]))
                  {
                    symbolName = demangle(realSymbolName);
                    if(realSymbolName != symbolName)
                    {
                      if(p > writepos)
                        fwrite(output.ptr + writepos, p - writepos, 1, stdout);
                      writepos = p;
                      fwrite(" (".ptr, 2, 1, stdout);
                      fwrite(symbolName.ptr, symbolName.length, 1, stdout);
                      fwrite(")".ptr, 1, 1, stdout);
                    }
                  }
                }
              }
        }
        if(writepos < output.length)
          fwrite(output.ptr + writepos, output.length - writepos, 1, stdout);
        fputc('\n', stdout);
      }
    }
    else
    {
      bSuccess = GetExitCodeProcess(piProcInfo.hProcess, &exitCode);
      if(!bSuccess || exitCode != 259) //259 == STILL_ACTIVE
        break;
      Sleep(5);
    }
  }


  //close the handles to the process
  CloseHandle(hStdInWrite);
  CloseHandle(hStdOutRead);
  CloseHandle(piProcInfo.hProcess);
  CloseHandle(piProcInfo.hThread);

  return exitCode;
}

///////////////////////////////////////////////////////////////////////////////
// inject DLL into linker process to monitor file reads

alias extern(Windows) DWORD function(LPVOID lpThreadParameter) LPTHREAD_START_ROUTINE;
extern(Windows) BOOL
WriteProcessMemory(HANDLE hProcess, LPVOID lpBaseAddress, LPCVOID lpBuffer, SIZE_T nSize, SIZE_T * lpNumberOfBytesWritten);
extern(Windows) HANDLE
CreateRemoteThread(HANDLE hProcess, LPSECURITY_ATTRIBUTES lpThreadAttributes, SIZE_T dwStackSize,
                   LPTHREAD_START_ROUTINE lpStartAddress, LPVOID lpParameter, DWORD dwCreationFlags, LPDWORD lpThreadId);

void InjectDLL(HANDLE hProcess, string depsfile)
{
    HANDLE hThread, hRemoteModule;

    HMODULE appmod = GetModuleHandleA(null);
    wchar[] wmodname = new wchar[260];
    DWORD len = GetModuleFileNameW(appmod, wmodname.ptr, wmodname.length);
    if(len > wmodname.length)
    {
        wmodname = new wchar[len + 1];
        GetModuleFileNameW(null, wmodname.ptr, len + 1);
    }
    string modpath = to!string(wmodname);
    string dll = buildPath(std.path.dirName(modpath), "filemonitor.dll");
    // copy path to other process
    auto wdll = to!wstring(dll) ~ cast(wchar)0;
    auto wdllRemote = VirtualAllocEx(hProcess, null, wdll.length * 2, MEM_COMMIT, PAGE_READWRITE);
    WriteProcessMemory(hProcess, wdllRemote, wdll.ptr, wdll.length * 2, null);

    // load dll into other process, assuming LoadLibraryW is at the same address in all processes
    HMODULE mod = GetModuleHandleA("Kernel32");
    auto proc = GetProcAddress(mod, "LoadLibraryW");
    hThread = CreateRemoteThread(hProcess, null, 0, cast(LPTHREAD_START_ROUTINE)proc, wdllRemote, 0, null);
    WaitForSingleObject(hThread, INFINITE);

    // Get handle of the loaded module
    GetExitCodeThread(hThread, cast(DWORD*) &hRemoteModule);

    // Clean up
    CloseHandle(hThread);
    VirtualFreeEx(hProcess, wdllRemote, wdll.length * 2, MEM_RELEASE);

    void* pDumpFile = cast(char*)hRemoteModule + 0x3000; // offset taken from map file
    auto szDepsFile = toMBSz(depsfile);
    WriteProcessMemory(hProcess, pDumpFile, szDepsFile, strlen(szDepsFile) + 1, null);
}

