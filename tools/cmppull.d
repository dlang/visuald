//
// open pull request in the TortoiseGit "Diff to previous version" dialog 
//
// compile with: dmd -m64 cmppull.d libcurl.lib user32.lib
// (the 32-bit cur lib does not allow https)
//
module cmppull;

import std.conv, std.stdio, std.path, std.process;
import std.algorithm, std.array, std.range;
import std.string : strip, stripLeft;

import core.sys.windows.windows;
import std.windows.charset;
import std.net.curl;


extern(Windows) BOOL OpenClipboard(HWND hWndNewOwner);
extern(Windows) BOOL CloseClipboard();
extern(Windows) HANDLE GetClipboardData(UINT uFormat);
enum CF_TEXT = 1;

int main(string[] argv)
{
	string url;
	string basedir = getcwd();
	if(argv.length < 2 || argv[1] == "clipboard")
	{
		if(OpenClipboard(null))
		{
			auto buffer = cast(char*)GetClipboardData(CF_TEXT);
			url = strip(to!string(buffer));
			CloseClipboard();
		}
	}
	else
		url = argv[1];
	if(argv.length > 2)
		basedir = argv[2];

	if(url.empty || url.countUntil('\n') != -1)
	{
		writeln("Usage:");
		writeln("   cmppull [<web-page>|clipboard] [basedir]");
		return 0;
	}
	string repo = url.findSplitBefore("/pull/")[0];
	repo = repo.retro.findSplitBefore("/")[0].array.reverse.to!string;
	if(repo.empty)
		throw new Exception("cannot determine repository");

	string repodir = std.path.buildPath(basedir, repo);
	string gitdir = std.path.buildPath(repodir, ".git");
	if(!std.file.exists(gitdir) || !std.file.isDir(gitdir))
	{
		repodir = basedir;
		gitdir = std.path.buildPath(repodir, ".git");
	}
	if(!std.file.exists(gitdir) || !std.file.isDir(gitdir))
		throw new Exception("repository " ~ repodir ~ " does not exist");

	writeln("Retrieving data from ", url);

	//ubyte[] data = htmlget(url);
	auto data = std.net.curl.get(url);

	//string dst = "c:/tmp/pull";
	//std.file.write(dst, data);

	// assume utf8
	string txt = to!string(data);
	string commit = txt.find(`class="commit-ref `);
	commit = commit.findSplitBefore("</p>")[0];

	string tag = `<span class="css-truncate-target">`;
	string user, branch, refuser, refbranch;
	if(findSkip(commit, tag))
		refuser = commit.findSplitBefore("</span>")[0];
	if(findSkip(commit, tag))
		refbranch = commit.findSplitBefore("</span>")[0];
	if(findSkip(commit, tag))
		user = commit.findSplitBefore("</span>")[0];
	if(findSkip(commit, tag))
		branch = commit.findSplitBefore("</span>")[0];

	string sha = txt;
	if(sha.findSkip("head sha1: &quot;"))
		sha = sha.findSplitBefore("&quot;")[0];
	else
		sha = null;

	string merge = txt;
	string commits_tag = `<span id="commits_tab_counter"`;
	int commits = 0;
	if(merge.findSkip(commits_tag) && merge.findSkip(">"))
	{
		merge = merge.stripLeft;
		commits = merge.parse!int;
	}

	writeln(repo, ": comparing ", user, "/", branch, " with ", refuser, "/", refbranch, " ", commits, " commits");
	if(user.empty || branch.empty || refuser.empty || refbranch.empty || sha.empty || commits <= 0)
		throw new Exception("insufficient information found");

	string gitfetch = "git fetch https://github.com/" ~ user ~ "/" ~ repo ~ ".git " ~ branch;
	if(!runProcess(gitfetch, repodir, true))
		throw new Exception("failed to execute `" ~ gitfetch ~ "`");
	
	if(!existsPrevdiffWindow(repodir))
	{
		string diff = "tortoisegitproc /command:prevdiff /path:\"" ~ repodir ~ "\"";
		if(!runProcess(diff, repodir, false))
			throw new Exception("failed to execute `" ~ diff ~ "`");
	}
	if(!fillPrevdiffWindow(repodir, commits))
		throw new Exception("cannot fill diff dialog");

	return 0;
}

extern(Windows) UINT GetKBCodePage();

BOOL runProcess(string command, string workdir, bool wait)
{
	PROCESS_INFORMATION piProcInfo; 
	STARTUPINFO siStartInfo;
	BOOL bSuccess = FALSE; 

	// Set up members of the STARTUPINFO structure. 
	// This structure specifies the STDIN and STDOUT handles for redirection.

	siStartInfo.cb = STARTUPINFO.sizeof; 
	//siStartInfo.hStdError = GetStdHandle(STD_ERROR_HANDLE);
	//siStartInfo.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
	//siStartInfo.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
	//siStartInfo.dwFlags |= STARTF_USESTDHANDLES;

	int cp = GetKBCodePage();
	auto szCommand = toMBSz(command, cp);
	auto szWorkDir = toMBSz(workdir, cp);
	bSuccess = CreateProcessA(null, 
								cast(char*)szCommand,     // command line 
								null,          // process security attributes 
								null,          // primary thread security attributes 
								TRUE,          // handles are inherited 
								0,             // creation flags 
								null,          // use parent's environment 
								szWorkDir,     // use parent's current directory 
								&siStartInfo,  // STARTUPINFO pointer 
								&piProcInfo);  // receives PROCESS_INFORMATION 
	if(bSuccess && wait)
	{
		bSuccess = WaitForSingleObject(piProcInfo.hProcess, 60000) == WAIT_OBJECT_0;
		if(bSuccess)
		{
			DWORD exitCode;
			bSuccess = GetExitCodeProcess(piProcInfo.hProcess, &exitCode) && exitCode == 0;
		}
	}

	return bSuccess;
}

extern(Windows)
{
	HWND FindWindowA(LPCSTR, LPCSTR);
	HWND FindWindowExA(HWND, HWND, LPCSTR, LPCSTR);
	int GetWindowTextA(HWND, LPSTR, int);
	HWND GetWindow(HWND, int);
}

enum GW_CHILD = 5;
enum GW_HWNDNEXT = 2;

HWND FindRecursive(HWND root, string name)
{
	auto h2 = FindWindowExA(root, null, null, name.ptr);
	if(h2)
		return h2;
	auto h = GetWindow(root, GW_CHILD);
	while(h)
	{
		char buf[100];
		int len = GetWindowTextA(h, buf.ptr, 100);
		//		writeln("  comparing to window ", h, " ", buf[0..len]);
		if(name == buf[0..len])
			return h;
		h2 = FindRecursive(h, name);
		if(h2)
			return h2;
		h2 = GetWindow(h, GW_HWNDNEXT);
		if(h2 == h)
			break;
		h = h2;
	}
	return null;
}

bool existsPrevdiffWindow(string repodir)
{
	string title = repodir ~ " - Changed Files - TortoiseGit";
	return FindWindowA("#32770", toMBSz(title)) !is null;
}

bool fillPrevdiffWindow(string repodir, int commits)
{
	string title = repodir ~ " - Changed Files - TortoiseGit";
	foreach(n; 0..100)
	{
		auto h = FindWindowA("#32770", toMBSz(title));
		if (h)
		{
			//wchar buf[100];
			//int len = GetWindowText(h, buf.ptr, 100);
			writeln("found window ", h);
			//			auto h2 = FindWindowExA(h, null, null, "\nabnormal program termination\n");
			auto h2 = GetDlgItem(h, 0x66b);
			if (h2)
			{
				auto sha = "FETCH_HEAD".ptr;
				SendMessageA(h2, WM_SETTEXT, 0, cast(LPARAM)sha);
			}
			auto h3 = GetDlgItem(h, 0x5be);
			if (h3)
			{
				auto sha = toMBSz(text("FETCH_HEAD~", commits));
				SendMessageA(h3, WM_SETTEXT, 0, cast(LPARAM)sha);
			}
			SetForegroundWindow(h);
			return h2 && h3;
		}
		Sleep(100);
	}
	return false;
}
