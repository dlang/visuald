//
// Written and provided by Benjamin Thaut
// Complications improved by Rainer Schuetze
//
// file access monitoring added by Rainer Schuetze, needs filemonitor.dll in the same
//  directory as pipedmd.exe, or tracker.exe from the MSBuild tool chain

module pipedmd;

import std.stdio;
import core.sys.windows.windows;
import core.sys.windows.wtypes;
import core.sys.windows.psapi;
import std.windows.charset;
import core.stdc.string;
import std.string;
import std.regex;
import core.demangle;
import std.array;
import std.algorithm;
import std.conv;
import std.path;
import std.process;
import std.utf;
static import std.file;

// version = pipeLink; // define to forward arguments to link.exe and demangle its output
version = MSLinkFormat;

enum canInjectDLL = false; // disable to rely on tracker.exe exclusively (keeps AV programs more happy)

alias core.stdc.stdio.stdout stdout;
alias core.stdc.stdio.stderr stderr;

static bool isIdentifierChar(char ch)
{
	// include C++,Pascal,Windows mangling and UTF8 encoding and compression
	return ch >= 0x80 || (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_';
}

static bool isDigit(char ch)
{
	return (ch >= '0' && ch <= '9');
}

string quoteArg(string arg)
{
	if(indexOf(arg, ' ') < arg.length)
		return "\"" ~ replace(arg, "\"", "\\\"") ~ "\"";
	else
		return arg;
}

string eatArg(string cmd)
{
	while (cmd.length && cmd[0] != ' ')
	{
		if (cmd[0] == '"')
		{
			cmd = cmd[1..$];
			while (cmd.length && cmd[0] != '"')
				cmd = cmd[1..$];
			if (cmd.length)
				cmd = cmd[1..$];
		}
		else
			cmd = cmd[1..$];
	}
	return cmd;
}

version(pipeLink)
{
	import core.stdc.stdlib : getenv;
	extern(C) int putenv(const char*);
	int main(string[] argv)
	{
		const(char)* p = getenv("dbuild_LinkToolExe");
		string link = p ? fromMBSz(cast(immutable)p) : "link.exe";
		// printf("pipelink called with: dbuild_LinkToolExe=%s\n", p);
		string cmd = to!string(GetCommandLineW());
		//printf("pipelink called with: %.*s\n", cast(int)cmd.length, cmd.ptr);
		cmd = link ~ eatArg(cmd);
		putenv("VS_UNICODE_OUTPUT="); // disable unicode output for link.exe
		int exitCode = runProcess(cmd, null, true, true, false, true, false);
		return exitCode;
	}

}
else
int main(string[] argv)
{
	if(argv.length < 2)
	{
		printf("pipedmd V0.2, written 2012 by Benjamin Thaut, complications improved by Rainer Schuetze\n");
		printf("decompresses and demangles names in OPTLINK and ld messages\n");
		printf("\n");
		printf("usage: %.*s [-nodemangle] [-gdcmode | -msmode] [-deps depfile] [executable] [arguments]\n",
			   argv[0].length, argv[0].ptr);
		return -1;
	}
	int skipargs = 0;
	string depsfile;
	bool doDemangle = true;
	bool demangleAll = false; //not just linker messages
	bool gdcMode = false; //gcc linker
	bool msMode = false; //microsoft linker
	bool verbose = false;
	bool memStats = false;

	while (argv.length >= skipargs + 2)
	{
		if(argv[skipargs + 1] == "-nodemangle")
		{
			doDemangle = false;
			skipargs++;
		}
		else if(argv[skipargs + 1] == "-demangleall")
		{
			demangleAll = true;
			skipargs++;
		}
		else if(argv[skipargs + 1] == "-gdcmode")
		{
			gdcMode = true;
			skipargs++;
		}
		else if(argv[skipargs + 1] == "-msmode")
		{
			msMode = true;
			skipargs++;
		}
		else if(argv[skipargs + 1] == "-verbose")
		{
			verbose = true;
			skipargs++;
		}
		else if(argv[skipargs + 1] == "-memStats")
		{
			memStats = true;
			skipargs++;
		}
		else if(argv[skipargs + 1] == "-deps")
			depsfile = argv[skipargs += 2];
		else
			break;
	}

	string exe = (argv.length > skipargs + 1 ? argv[skipargs + 1] : null);
	string command;
	string trackdir;
	string trackfile;
	string trackfilewr;
	string trackfiledel;

	bool inject = false;
	if (depsfile.length > 0)
	{
		string fullexe = findExeInPath(exe);
		bool isX64 = isExe64bit(fullexe);
		if (verbose)
		{
			if (fullexe.empty)
				printf ("%.*s not found in PATH, assuming %d-bit application\n", exe.length, exe.ptr, isX64 ? 64 : 32);
			else
				printf ("%.*s is a %d-bit application\n", fullexe.length, fullexe.ptr, isX64 ? 64 : 32);
		}
		string trackerArgs;
		string tracker = findTracker(isX64, trackerArgs);
		if (tracker.length > 0)
		{
			command = quoteArg(tracker);
			command ~= trackerArgs;
			command ~= " /m"; // include temporary files removed, they might appear as input to sub processes
			trackdir = dirName(depsfile);
			if (trackdir != ".")
				command ~= " /if " ~ quoteArg(trackdir);
			trackfile = "*.read.*.tlog";
			trackfilewr = "*.write.*.tlog";
			trackfiledel = "*.delete.*.tlog";
			foreach(f; std.file.dirEntries(trackdir, std.file.SpanMode.shallow))
				if (globMatch(baseName(f), trackfile) || globMatch(baseName(f), trackfilewr) || globMatch(baseName(f), trackfiledel))
					std.file.remove(f.name);
			command ~= " /c";
		}
		else if (isX64 || !canInjectDLL)
		{
			printf("cannot monitor %d-bit executable %.*s, no suitable tracker.exe found\n", isX64 ? 64 : 32, exe.length, exe.ptr);
			return -1;
		}
		else
			inject = true;
	}

	for(int i = skipargs + 1;i < argv.length; i++)
	{
		if(command.length > 0)
			command ~= " ";
		command ~= quoteArg(argv[i]);
	}
	if(verbose)
		printf("Command: %.*s\n", command.length, command.ptr);

	int exitCode = runProcess(command, inject ? depsfile : null, doDemangle, demangleAll, gdcMode, msMode, memStats);

	if (exitCode == 0 && trackfile.length > 0)
	{
		// read read.*.tlog and remove all files found in write.*.log or delete.*.log
		string rdbuf;
		string wrbuf;
		foreach(f; std.file.dirEntries(trackdir, std.file.SpanMode.shallow))
		{
			bool rd = globMatch(baseName(f), trackfile);
			bool wr = globMatch(baseName(f), trackfilewr);
			bool del = globMatch(baseName(f), trackfiledel);
			if (rd || wr || del)
			{
				ubyte[] fbuf = cast(ubyte[])std.file.read(f.name);
				string cbuf;
				// strip BOM from all but the first file
				if(fbuf.length > 1 && fbuf[0] == 0xFF && fbuf[1] == 0xFE)
					cbuf = to!(string)(cast(wstring)(fbuf[2..$]));
				else
					cbuf = cast(string)fbuf;
				if(rd)
					rdbuf ~= cbuf;
				else
					wrbuf ~= cbuf;
			}
		}
		string[] rdlines = splitLines(rdbuf, KeepTerminator.yes);
		string[] wrlines = splitLines(wrbuf, KeepTerminator.yes);
		bool[string] wrset;
		foreach(w; wrlines)
			if (!w.startsWith("#Command:"))
				wrset[w] = true;

		bool[string] rdset;
		foreach(r; rdlines)
			if (!r.startsWith("#Command:"))
				if(r !in wrset)
					rdset[r] = true;

		string buf = rdset.keys.sort.join;

		std.file.write(depsfile, buf);
	}

	return exitCode;
}

int runProcess(string command, string depsfile, bool doDemangle, bool demangleAll, bool gdcMode, bool msMode, bool memStats)
{
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
	STARTUPINFOW siStartInfo;
	BOOL bSuccess = FALSE;

	// Set up members of the PROCESS_INFORMATION structure.

	memset( &piProcInfo, 0, PROCESS_INFORMATION.sizeof );

	// Set up members of the STARTUPINFO structure.
	// This structure specifies the STDIN and STDOUT handles for redirection.

	memset( &siStartInfo, 0, STARTUPINFOW.sizeof );
	siStartInfo.cb = STARTUPINFOW.sizeof;
	siStartInfo.hStdError = hStdOutWrite;
	siStartInfo.hStdOutput = hStdOutWrite;
	siStartInfo.hStdInput = hStdInRead;
	siStartInfo.dwFlags |= STARTF_USESTDHANDLES;

	int cp = GetKBCodePage();
	auto szCommand = toUTF16z(command);
	bSuccess = CreateProcessW(null,
							  cast(wchar*)szCommand,     // command line
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
		printf("failed launching %ls\n", szCommand);
		return 1;
	}

	static if(canInjectDLL)
		if(depsfile)
			InjectDLL(piProcInfo.hProcess, depsfile);
	ResumeThread(piProcInfo.hThread);

	ubyte[] buffer = new ubyte[2048];
	DWORD bytesFilled = 0;
	DWORD bytesAvailable = 0;
	DWORD bytesRead = 0;
	DWORD exitCode = 0;
	bool linkerFound = gdcMode || msMode || demangleAll;

	L_loop:
	while(true)
	{
		DWORD dwlen = cast(DWORD)buffer.length;
		bSuccess = PeekNamedPipe(hStdOutRead, buffer.ptr + bytesFilled, dwlen - bytesFilled, &bytesRead, &bytesAvailable, null);
		if (bSuccess && bytesRead > 0)
			bSuccess = ReadFile(hStdOutRead, buffer.ptr + bytesFilled, dwlen - bytesFilled, &bytesRead, null);
		if(bSuccess && bytesRead > 0)
		{
			DWORD lineLength = bytesFilled; // no need to search before previous end
			bytesFilled += bytesRead;
			for(; lineLength < buffer.length && lineLength < bytesFilled; lineLength++)
			{
				if (buffer[lineLength] == '\n')
				{
					size_t len = lineLength + 1;
					demangleLine(buffer[0 .. len], doDemangle, demangleAll, msMode, gdcMode, cp, linkerFound);
					memmove(buffer.ptr, buffer.ptr + len, bytesFilled - len);
					bytesFilled -= len;
					lineLength = 0;
				}
			}
			// if no line end found, retry with larger buffer
			if(bytesFilled >= buffer.length)
			{
				buffer.length = buffer.length * 2;
				continue;
			}
		}

		bSuccess = GetExitCodeProcess(piProcInfo.hProcess, &exitCode);
		if(!bSuccess || exitCode != 259) //259 == STILL_ACTIVE
		{
			// process trailing text if not terminated by a newline
			if (bytesFilled > 0)
				demangleLine(buffer[0 .. bytesFilled], doDemangle, demangleAll, msMode, gdcMode, cp, linkerFound);
			break;
		}
		Sleep(5);
	}

	if (memStats)
		if (auto fun = getProcessMemoryInfoFunc())
		{
			string procName = getProcessName(piProcInfo.hProcess);
			PROCESS_MEMORY_COUNTERS memCounters;
			bSuccess = fun(piProcInfo.hProcess, &memCounters, memCounters.sizeof);
			if (bSuccess)
				printf("%s used %lld MB of private memory\n", procName.ptr,
					   cast(long)memCounters.PeakPagefileUsage >> 20);
		}

	//close the handles to the process
	CloseHandle(hStdInWrite);
	CloseHandle(hStdOutRead);
	CloseHandle(piProcInfo.hProcess);
	CloseHandle(piProcInfo.hThread);

	return exitCode;
}

void demangleLine(ubyte[] output, bool doDemangle, bool demangleAll, bool msMode, bool gdcMode, int cp, ref bool linkerFound)
{
	if (output.length && output[$-1] == '\n')  //remove trailing \n
		output = output[0 .. $-1];
	while(output.length && output[$-1] == '\r')  //remove trailing \r
		output = output[0 .. $-1];

	while(output.length && output[0] == '\r') // remove preceding \r
		output = output[1 .. $];

	if(msMode) //the microsoft linker outputs the error messages in the default ANSI codepage so we need to convert it to UTF-8
	{
		static WCHAR[] decodeBufferWide;
		static ubyte[] decodeBuffer;

		if(decodeBufferWide.length < output.length + 1)
		{
			decodeBufferWide.length = output.length + 1;
			decodeBuffer.length = 2 * output.length + 1;
		}
		auto numDecoded = MultiByteToWideChar(CP_ACP, 0, cast(char*)output.ptr, cast(DWORD)output.length, decodeBufferWide.ptr, cast(DWORD)decodeBufferWide.length);
		auto numEncoded = WideCharToMultiByte(CP_UTF8, 0, decodeBufferWide.ptr, numDecoded, cast(char*)decodeBuffer.ptr, cast(DWORD)decodeBuffer.length, null, null);
		output = decodeBuffer[0..numEncoded];
	}
	size_t writepos = 0;

	if(!linkerFound)
	{
		if (output.startsWith("OPTLINK (R)"))
			linkerFound = true;
		else if(output.countUntil("error LNK") >= 0 || output.countUntil("warning LNK") >= 0)
			linkerFound = msMode = true;
	}

	if(doDemangle && linkerFound)
	{
		if(gdcMode)
		{
			if(demangleAll || output.countUntil("undefined reference to") >= 0 || output.countUntil("In function") >= 0)
			{
				processLine(output, writepos, false, cp);
			}
		}
		else if(msMode)
		{
			if(demangleAll || output.countUntil("LNK") >= 0)
			{
				processLine(output, writepos, false, cp);
			}
		}
		else
		{
			processLine(output, writepos, true, cp);
		}
	}
	if(writepos < output.length)
		fwrite(output.ptr + writepos, output.length - writepos, 1, stdout);
	fputc('\n', stdout);
}

void processLine(ubyte[] output, ref size_t writepos, bool optlink, int cp)
{
	for(int p = 0; p < output.length; p++)
	{
		if(isIdentifierChar(output[p]))
		{
			int q = p;
			while(p < output.length && isIdentifierChar(output[p]))
				p++;

			auto symbolName = cast(const(char)[]) output[q..p];
			const(char)[] realSymbolName = symbolName;
			if(optlink)
			{
				size_t pos = 0;
				realSymbolName = decodeDmdString(symbolName, pos);
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
						realSymbolName = null;
					}
				}
			}
			if(realSymbolName.length)
			{
				version(MSLinkFormat) {} else
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
					try
					{
						symbolName = demangle(realSymbolName);
					}
					catch(Exception)
					{
					}
					if(realSymbolName != symbolName)
					{
						version(MSLinkFormat)
						{
							if(q > writepos)
								fwrite(output.ptr + writepos, q - writepos, 1, stdout);
							writepos = q;
							fwrite("\"".ptr, 1, 1, stdout);
							fwrite(symbolName.ptr, symbolName.length, 1, stdout);
							fwrite("\" (".ptr, 3, 1, stdout);
							if(p > writepos)
								fwrite(output.ptr + writepos, p - writepos, 1, stdout);
							writepos = p;
							fwrite(")".ptr, 1, 1, stdout);
						}
						else
						{
							// skip a trailing quote
							if(p + 1 < output.length && (output[p+1] == '\'' || output[p+1] == '\"'))
								p++;

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
	}
}

///////////////////////////////////////////////////////////////////////////////
bool isExe64bit(string exe)
//out(res) { 	printf("isExe64bit: %.*s %d-bit\n", exe.length, exe.ptr, res ? 64 : 32); }
body
{
	if (exe is null || !std.file.exists(exe))
		return false;

	try
	{
		File f = File(exe, "rb");
		IMAGE_DOS_HEADER dosHdr;
		f.rawRead((&dosHdr)[0..1]);
		if (dosHdr.e_magic != IMAGE_DOS_SIGNATURE)
			return false;
		f.seek(dosHdr.e_lfanew);
		IMAGE_NT_HEADERS ntHdr;
		f.rawRead((&ntHdr)[0..1]);
		return ntHdr.FileHeader.Machine == IMAGE_FILE_MACHINE_AMD64
			|| ntHdr.FileHeader.Machine == IMAGE_FILE_MACHINE_IA64;
	}
	catch(Exception)
	{
	}
	return false;
}

string findExeInPath(string exe)
{
	if (std.path.baseName(exe) != exe)
		return exe; // if the file has dir component, don't search path

	string path = std.process.environment["PATH"];
	string[] paths = split(path, ";");
	string ext = extension(exe);

	foreach(p; paths)
	{
		p = strip(p, '"');
		if (p.length == 0)
			continue;
		
		p = std.path.buildPath(p, exe);
		if(std.file.exists(p))
			return p;

		if (ext.empty)
		{
			if(std.file.exists(p ~ ".exe"))
				return p ~ ".exe";
			if(std.file.exists(p ~ ".com"))
				return p ~ ".com";
			if(std.file.exists(p ~ ".bat"))
				return p ~ ".bat";
			if(std.file.exists(p ~ ".cmd"))
				return p ~ ".cmd";
		}
	}
	return null;
}

enum SECURE_ACCESS = ~(WRITE_DAC | WRITE_OWNER | GENERIC_ALL | ACCESS_SYSTEM_SECURITY);
enum KEY_WOW64_32KEY = 0x200;
enum KEY_WOW64_64KEY = 0x100;

string findTracker(bool x64, ref string trackerArgs)
{
	string exe = findExeInPath("tracker.exe");
	if (!exe.empty && isExe64bit(exe) != x64)
		exe = null;
	if (exe.indexOf("14.0") >= 0)
		trackerArgs = x64 ? " /d FileTracker64.dll" : " /d FileTracker32.dll";

	if (exe.empty)
		exe = findTrackerInVS2017();
	if (exe.empty)
		exe = findTrackerInMSBuild(r"SOFTWARE\Microsoft\MSBuild\ToolsVersions\14.0"w.ptr, x64, &trackerArgs);
	if (exe.empty)
		exe = findTrackerInMSBuild(r"SOFTWARE\Microsoft\MSBuild\ToolsVersions\12.0"w.ptr, x64, null);
	if (exe.empty)
		exe = findTrackerInMSBuild(r"SOFTWARE\Microsoft\MSBuild\ToolsVersions\11.0"w.ptr, x64, null);
	if (exe.empty)
		exe = findTrackerInMSBuild(r"SOFTWARE\Microsoft\MSBuild\ToolsVersions\10.0"w.ptr, x64, null);
	if (exe.empty)
		exe = findTrackerInSDK(x64);
	if (exe.empty)
		exe = findTrackerViaCOM(x64);
	return exe;
}

string trackerPath(string binpath, bool x64)
{
	if (binpath.empty)
		return null;
	string exe = buildPath(binpath, "tracker.exe");
	//printf("trying %.*s\n", exe.length, exe.ptr);
	if (!std.file.exists(exe))
		return null;
	if (isExe64bit(exe) != x64)
		return null;
	return exe;
}

string findTrackerInMSBuild(const(wchar)* keyname, bool x64, string* trackerArgs)
{
	string path = readRegistry(keyname, "MSBuildToolsPath"w.ptr, x64);
	string exe = trackerPath(path, x64);
	if (exe && trackerArgs)
		*trackerArgs = x64 ? " /d FileTracker64.dll" : " /d FileTracker32.dll";
	return exe;
}

string findTrackerInVS2017()
{
	wstring key = r"SOFTWARE\Microsoft\VisualStudio\SxS\VS7";
	string dir = readRegistry(key.ptr, "15.0"w.ptr, false); // always in Wow6432
	if (dir.empty)
		return null;
	string exe = dir ~ r"MSBuild\15.0\Bin\Tracker.exe";
	if (!std.file.exists(exe))
		return null;
	// can handle both x86 and x64
	return exe;
}

string findTrackerInSDK(bool x64)
{
	wstring suffix = x64 ? "-x64" : "-x86";
	wstring sdk = r"SOFTWARE\Microsoft\Microsoft SDKs\Windows";
	HKEY key;
	LONG lRes = RegOpenKeyExW(HKEY_LOCAL_MACHINE, sdk.ptr, 0,
							  KEY_READ | KEY_WOW64_32KEY, &key); // always in Wow6432
	if (lRes != ERROR_SUCCESS)
		return null;

	string exe;
	DWORD idx = 0;
	wchar[100] ver;
	DWORD len = ver.length;
	while (RegEnumKeyExW(key, idx, ver.ptr, &len, null, null, null, null) == ERROR_SUCCESS)
	{
		const(wchar)[] sdkver = sdk ~ r"\"w ~ ver[0..len];
		const(wchar)* wsdkver = toUTF16z(sdkver);
		HKEY verkey;
		lRes = RegOpenKeyExW(HKEY_LOCAL_MACHINE, wsdkver, 0, KEY_READ | KEY_WOW64_32KEY, &verkey); // always in Wow6432
		if (lRes == ERROR_SUCCESS)
		{
			DWORD veridx = 0;
			wchar[100] sub;
			len = sub.length;
			while (RegEnumKeyExW(verkey, veridx, sub.ptr, &len, null, null, null, null) == ERROR_SUCCESS)
			{
				const(wchar)[] sdkversub = sdkver ~ r"\"w ~ sub[0..len];
				string path = readRegistry(toUTF16z(sdkversub), "InstallationFolder"w.ptr, false);
				exe = trackerPath(path, x64);
				if (!exe.empty)
					break;
				veridx++;
			}
			RegCloseKey(verkey);
		}
		idx++;
		if (!exe.empty)
			break;
	}
	RegCloseKey(key);

	return exe;
}

string readRegistry(const(wchar)* keyname, const(wchar)* valname, bool x64)
{
	string path;
	HKEY key;
	LONG lRes = RegOpenKeyExW(HKEY_LOCAL_MACHINE, keyname, 0,
							  KEY_READ | (x64 ? KEY_WOW64_64KEY : KEY_WOW64_32KEY), &key);
	//printf("RegOpenKeyExW = %d, key=%x\n", lRes, key);
	if (lRes == ERROR_SUCCESS)
	{
		DWORD type;
		DWORD cntBytes;
		int hr = RegQueryValueExW(key, valname, null, &type, null, &cntBytes);
		//printf("RegQueryValueW = %d, %d words\n", hr, cntBytes);
		if (hr == ERROR_SUCCESS || hr == ERROR_MORE_DATA)
		{
			wchar[] wpath = new wchar[(cntBytes + 1) / 2];
			hr = RegQueryValueExW(key, valname, null, &type, wpath.ptr, &cntBytes);
			if (hr == ERROR_SUCCESS)
				path = toUTF8(wpath[0..$-1]); // strip trailing 0
		}
		RegCloseKey(key);
	}
	return path;
}

///////////////////////////////////////////////////////////////////////
interface ISetupInstance : IUnknown
{
	// static const GUID iid = uuid("B41463C3-8866-43B5-BC33-2B0676F7F42E");
	static const GUID iid = { 0xB41463C3, 0x8866, 0x43B5, [ 0xBC, 0x33, 0x2B, 0x06, 0x76, 0xF7, 0xF4, 0x2E ] };

    int GetInstanceId(BSTR* pbstrInstanceId);
    int GetInstallDate(LPFILETIME pInstallDate);
    int GetInstallationName(BSTR* pbstrInstallationName);
    int GetInstallationPath(BSTR* pbstrInstallationPath);
    int GetInstallationVersion(BSTR* pbstrInstallationVersion);
    int GetDisplayName(LCID lcid, BSTR* pbstrDisplayName);
    int GetDescription(LCID lcid, BSTR* pbstrDescription);
    int ResolvePath(LPCOLESTR pwszRelativePath, BSTR* pbstrAbsolutePath);
}

interface IEnumSetupInstances : IUnknown
{
	// static const GUID iid = uuid("6380BCFF-41D3-4B2E-8B2E-BF8A6810C848");

    int Next(ULONG celt, ISetupInstance* rgelt, ULONG* pceltFetched);
    int Skip(ULONG celt);
    int Reset();
    int Clone(IEnumSetupInstances* ppenum);
}

interface ISetupConfiguration : IUnknown
{
	// static const GUID iid = uuid("42843719-DB4C-46C2-8E7C-64F1816EFD5B");
	static const GUID iid = { 0x42843719, 0xDB4C, 0x46C2, [ 0x8E, 0x7C, 0x64, 0xF1, 0x81, 0x6E, 0xFD, 0x5B ] };

    int EnumInstances(IEnumSetupInstances* ppEnumInstances) ;
	int GetInstanceForCurrentProcess(ISetupInstance* ppInstance);
	int GetInstanceForPath(LPCWSTR wzPath, ISetupInstance* ppInstance);
};

const GUID iid_SetupConfiguration = { 0x177F0C4A, 0x1CD3, 0x4DE7, [ 0xA3, 0x2C, 0x71, 0xDB, 0xBB, 0x9F, 0xA3, 0x6D ] };

string findTrackerViaCOM(bool x64)
{
	CoInitialize(null);
	scope(exit) CoUninitialize();

	ISetupConfiguration setup;
	IEnumSetupInstances instances;
	ISetupInstance instance;
	DWORD fetched;

    HRESULT hr = CoCreateInstance(&iid_SetupConfiguration, null, CLSCTX_ALL, &ISetupConfiguration.iid, cast(void**) &setup);
	if (hr != S_OK || !setup)
		return null;
	scope(exit) setup.Release();

	if (setup.EnumInstances(&instances) != S_OK)
		return null;
	scope(exit) instances.Release();

	while (instances.Next(1, &instance, &fetched) == S_OK && fetched)
	{
		BSTR installDir;
		if (instance.GetInstallationPath(&installDir) != S_OK)
			continue;

		char[260] path;
		int len = WideCharToMultiByte(CP_UTF8, 0, installDir, -1, path.ptr, 260, null, null);
		SysFreeString(installDir);

		if (len > 0)
		{
			// printf("found VS: %s %d\n", path.ptr, path[len-1]);
			string dir = path[0..len-1].idup;
			string exe = dir ~ r"\MSBuild\15.0\Bin\Tracker.exe";
			if (std.file.exists(exe))
				return exe; // VS2017

			exe = dir ~ r"\MSBuild\Current\Bin\Tracker.exe";
			if (std.file.exists(exe))
				return exe; // VS2019
		}
	}

	return null;
}

///////////////////////////////////////////////////////////////////////////////
// inject DLL into linker process to monitor file reads

static if(canInjectDLL)
{
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

	auto wdll = to!wstring(dll) ~ cast(wchar)0;
	// detect offset of dumpFile
	HMODULE fmod = LoadLibraryW(wdll.ptr);
	if(!fmod)
		return;
	size_t addr = cast(size_t)GetProcAddress(fmod, "_D11filemonitor8dumpFileG260a");
	FreeLibrary(fmod);
	if(addr == 0)
		return;
	addr = addr - cast(size_t)fmod;

	// copy path to other process
	auto wdllRemote = VirtualAllocEx(hProcess, null, wdll.length * 2, MEM_COMMIT, PAGE_READWRITE);
	auto procWrite = getWriteProcFunc();
	procWrite(hProcess, wdllRemote, wdll.ptr, wdll.length * 2, null);

	// load dll into other process, assuming LoadLibraryW is at the same address in all processes
	HMODULE mod = GetModuleHandleA("Kernel32");
	auto proc = GetProcAddress(mod, "LoadLibraryW");
	hThread = getCreateRemoteThreadFunc()(hProcess, null, 0, cast(LPTHREAD_START_ROUTINE)proc, wdllRemote, 0, null);
	WaitForSingleObject(hThread, INFINITE);

	// Get handle of the loaded module
	GetExitCodeThread(hThread, cast(DWORD*) &hRemoteModule);

	// Clean up
	CloseHandle(hThread);
	VirtualFreeEx(hProcess, wdllRemote, wdll.length * 2, MEM_RELEASE);

	void* pDumpFile = cast(char*)hRemoteModule + addr;
	// printf("remotemod = %p, addr = %p\n", hRemoteModule, pDumpFile);
	auto szDepsFile = toMBSz(depsfile);

	procWrite(hProcess, pDumpFile, szDepsFile, strlen(szDepsFile) + 1, null);
}

typeof(WriteProcessMemory)* getWriteProcFunc ()
{
	HMODULE mod = GetModuleHandleA("Kernel32");
	auto proc = GetProcAddress(mod, "WriteProcessMemory");
	return cast(typeof(WriteProcessMemory)*)proc;
}

typeof(CreateRemoteThread)* getCreateRemoteThreadFunc ()
{
	HMODULE mod = GetModuleHandleA("Kernel32");
	auto proc = GetProcAddress(mod, "CreateRemoteThread");
	return cast(typeof(CreateRemoteThread)*)proc;
}

} // static if(canInjectDLL)

typeof(GetProcessMemoryInfo)* getProcessMemoryInfoFunc ()
{
	HMODULE mod = GetModuleHandleA("psapi");
	if (!mod)
		mod = LoadLibraryA("psapi.dll");
	auto proc = GetProcAddress(mod, "GetProcessMemoryInfo");
	return cast(typeof(GetProcessMemoryInfo)*)proc;
}

string getProcessName(HANDLE process)
{
	HMODULE mod = GetModuleHandleA("psapi");
	if (!mod)
		mod = LoadLibraryA("psapi.dll");
	auto proc = GetProcAddress(mod, "GetProcessImageFileNameW");
	if (!proc)
		return "child process";
	wchar[260] imageName;
	auto fn = cast(typeof(GetProcessImageFileNameW)*)proc;
	DWORD len = fn(process, imageName.ptr, imageName.length);
	if (len == 0)
		return "child process";
	auto pos = lastIndexOf(imageName[0..len], '\\');
	return to!string(imageName[pos+1..len]);
}
