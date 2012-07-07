//
// Written and provided by Benjamin Thaut
//

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

alias std.c.stdio.stdout stdout;

static bool isIdentifierChar(char ch)
{
  // include C++,Pascal,Windows mangling and UTF8 encoding and compression 
  return ch >= 0x80 || (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
}

int main(string[] argv)
{
  if(argv.length < 2)
  {
    printf("pipedmd V0.1, written 2012 by Benjamin Thaut, complications improved by Rainer Schuetze\n");
    printf("decompresses and demangles names in the DMD error messages\n");
    printf("\n");
    printf("usage: %s [executable] [arguments]\n", argv[0].ptr);
    return -1;
  }
  string command; // = "dmd";
  for(int i=1;i<argv.length;i++)
  {
    if(i > 1)
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

  auto szCommand = toStringz(command);
  bSuccess = CreateProcessA(null, 
                            cast(char*)szCommand,     // command line 
                            null,          // process security attributes 
                            null,          // primary thread security attributes 
                            TRUE,          // handles are inherited 
                            0,             // creation flags 
                            null,          // use parent's environment 
                            null,          // use parent's current directory 
                            &siStartInfo,  // STARTUPINFO pointer 
                            &piProcInfo);  // receives PROCESS_INFORMATION 

  if(!bSuccess)
  {
    printf("failed launching %s\n", szCommand);
    return 1;
  }

  char[] buffer = new char[2048];
  DWORD bytesRead = 0;
  DWORD bytesAvaiable = 0;
  DWORD exitCode = 0;
  bool optlinkFound = false;

  int cp = GetKBCodePage();
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
      while(bytesRead > 0 && buffer[bytesRead] == '\r') // remove \r
        bytesRead--; 
      DWORD skip = 0;
	  while(skip < bytesRead && buffer[skip] == '\r') // remove \r
	    skip++;

      char[] output = buffer[skip..bytesRead];
      size_t writepos = 0;

      if(output.startsWith("OPTLINK (R)"))
        optlinkFound = true;

	  if(optlinkFound)
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
			  if(realSymbolName.length > 2 && realSymbolName[0] == '_' && realSymbolName[1] == 'D')
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
	  if(writepos < output.length)
		fwrite(output.ptr + writepos, output.length - writepos, 1, stdout);
	  //fputc('\n', stdout);
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
