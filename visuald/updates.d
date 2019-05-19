// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.updates;

import visuald.windows;
import visuald.dpackage;

import std.conv;
import std.datetime;
import std.file;
import std.json;
import std.path;
import std.process;
import std.string;
import std.utf;
import core.thread;

enum CheckFrequency
{
	Never,
	Daily,
	Weekly,
	DailyPrereleases
}

Duration toDuration(CheckFrequency freq)
{
	switch(freq)
	{
		default:
		case CheckFrequency.Never: return Duration.max;
		case CheckFrequency.Daily: return 1.days;
		case CheckFrequency.Weekly: return 7.days;
		case CheckFrequency.DailyPrereleases: return 1.days;
	}
}

enum CheckProduct
{
	VisualD,
	DMD,
	LDC,
}

struct UpdateInfo
{
	string name;
	string published;
	string download_url;
	SysTime lastCheck;
	bool updated;
}

UpdateInfo* checkForUpdate(CheckProduct prod, Duration renew, int frequency)
{
	bool prereleases = frequency == CheckFrequency.DailyPrereleases;
	string updateDir = std.path.buildPath(environment["APPDATA"], "VisualD", "Updates");
	if (!std.file.exists(updateDir))
		mkdirRecurse(updateDir);

	string domain, url, tgt;
	switch (prod)
	{
		case CheckProduct.VisualD:
			domain = "api.github.com";
			url = "/repos/D-Programming-Language/visuald/releases";
			tgt = std.path.buildPath(updateDir, "visuald.releases");
			break;
		case CheckProduct.LDC:
			domain = "api.github.com";
			url = "/repos/ldc-developers/ldc/releases";
			tgt = std.path.buildPath(updateDir, "ldc.releases");
			break;
		case CheckProduct.DMD:
			domain = "downloads.dlang.org";
			url = prereleases ? "/pre-releases/LATEST" : "/releases/LATEST";
			tgt = std.path.buildPath(updateDir, prereleases ? "dmd.prereleases" : "dmd.releases");
			break;
		default:
			return null;
	}

	bool updated = false;
	bool cachedOnly = renew < 0.days;
	SysTime modTime;
	char[] data;
	if (std.file.exists(tgt))
	{
		SysTime accessTime;
		std.file.getTimes(tgt, accessTime, modTime);
		if (cachedOnly || modTime + renew >= Clock.currTime)
			data = cast(char[]) std.file.read(tgt);
	}
	else
		modTime = Clock.currTime;

	if (!data && !cachedOnly)
	{
		data = winHttpGet(domain, url, prod != CheckProduct.DMD);
		if (data)
			std.file.write(tgt, data);
		updated = true;
	}
	if (!data)
		return null;

	string txt = to!string(data);

	if (prod == CheckProduct.DMD)
	{
		auto info = new UpdateInfo;
		info.name = "DMD " ~ txt;
		info.download_url = "http://" ~ domain ~ url[0..$-6] ~ "2.x/" ~ txt ~ "/dmd." ~ txt ~ ".windows.7z";
		info.lastCheck = modTime;
		info.updated = updated;
		return info;
	}
	JSONValue j = parseJSON(txt);
	foreach(r; j.array())
	{
		if (r["prerelease"].boolean() && !prereleases)
			continue;
		auto assets = r["assets"].array();
		string needle = prod == CheckProduct.LDC ? "windows-multilib" : ".exe";
		foreach (asset; assets)
		{
			if (asset["browser_download_url"].str().indexOf(needle) >= 0)
			{
				auto info = new UpdateInfo;
				info.name = r["name"].str();
				info.published = r["published_at"].str()[0..10]; // remove time
				info.download_url = asset["browser_download_url"].str();
				debug(UPDATE) writeln(info.published, " ", info.name, " ", info.download_url);
				info.lastCheck = modTime;
				info.updated = updated;
				return info;
			}
		}
	}

	return null;
}

import core.sys.windows.winhttp;
import core.stdc.stdio;

private shared(uint) updateCancelCounter;

void cancelAllUpdates()
{
	updateCancelCounter = updateCancelCounter + 1;
}

char[] winHttpGet(string server, string request, bool https)
{
	DownloadRequest req;
	req.server = toUTF16z(server);
	req.request = toUTF16z(request);
	req.port = https ? INTERNET_DEFAULT_HTTPS_PORT : INTERNET_DEFAULT_HTTP_PORT;
	req.cancelCounter = updateCancelCounter;

	winHttpGet(&req);
	return req.data;
}

void winHttpGet(DownloadRequest* req)
{
	debug(UPDATE) printf("winHttpGet %S %S %d\n", req.server, req.request, req.port);
	HINTERNET hSession = null;
	HINTERNET hConnect = null;
	HINTERNET hRequest = null;

	// Use WinHttpOpen to obtain a session handle.
	hSession = WinHttpOpen("Visual D"w.ptr,
						   WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
						   WINHTTP_NO_PROXY_NAME, 
						   WINHTTP_NO_PROXY_BYPASS, 0);
	scope(exit) if(hSession) WinHttpCloseHandle(hSession);

	DWORD opt = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
	WinHttpSetOption(hSession, WINHTTP_OPTION_REDIRECT_POLICY, &opt, opt.sizeof);

	opt = /*SECURITY_FLAG_IGNORE_WEAK_SIGNATURE |*/ SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE | SECURITY_FLAG_IGNORE_UNKNOWN_CA
		| SECURITY_FLAG_IGNORE_CERT_CN_INVALID | SECURITY_FLAG_IGNORE_CERT_DATE_INVALID;
	WinHttpSetOption(hSession, WINHTTP_OPTION_SECURITY_FLAGS, &opt, opt.sizeof);

	// Specify an HTTP server.
	if(hSession && !req.cancel)
		hConnect = WinHttpConnect(hSession, req.server, req.port, 0);
	scope(exit) if(hConnect) WinHttpCloseHandle(hConnect);

	// Create an HTTP request handle.
	if(hConnect && !req.cancel)
		hRequest = WinHttpOpenRequest(hConnect, "GET"w.ptr, req.request,
									  null, WINHTTP_NO_REFERER, 
									  WINHTTP_DEFAULT_ACCEPT_TYPES, 
									  req.port == INTERNET_DEFAULT_HTTPS_PORT ? WINHTTP_FLAG_SECURE : 0);
	scope(exit) if(hRequest) WinHttpCloseHandle(hRequest);

	// Send a request.
	BOOL bResults = false;
	if(hRequest && !req.cancel)
		bResults = WinHttpSendRequest(hRequest,
									  WINHTTP_NO_ADDITIONAL_HEADERS, 0,
									  WINHTTP_NO_REQUEST_DATA, 0, 0, 0 );

	// End the request.
	if(bResults && !req.cancel)
		bResults = WinHttpReceiveResponse(hRequest, null);

	DWORD dwSize = 0;
	if(bResults && !req.cancel)
	{
		bResults = WinHttpQueryHeaders(hRequest, WINHTTP_QUERY_RAW_HEADERS_CRLF,
									   WINHTTP_HEADER_NAME_BY_INDEX, null,
									   &dwSize, WINHTTP_NO_HEADER_INDEX);

		// Allocate memory for the buffer.
		if(GetLastError() == ERROR_INSUFFICIENT_BUFFER)
		{
			auto header = new wchar[dwSize/wchar.sizeof];

			// Now, use WinHttpQueryHeaders to retrieve the header.
			bResults = WinHttpQueryHeaders(hRequest,
										   WINHTTP_QUERY_RAW_HEADERS_CRLF,
										   WINHTTP_HEADER_NAME_BY_INDEX,
										   header.ptr, &dwSize,
										   WINHTTP_NO_HEADER_INDEX);
			debug(UPDATE) writeln("Header: ", header);
			auto lines = header.splitLines();
			foreach(ln; lines)
				if (ln.startsWith("Content-Length:"))
				{
					auto lenstr = strip(ln[15..$]);
					req.fullSize = parse!DWORD(lenstr);
				}
		}
	}

	// Report any errors.
	if(!bResults && !req.cancel)
		throw new Exception("HTTP Error has occurred:" ~ to!string(GetLastError()));

	// Keep checking for data until there is nothing left.
	for ( ; !req.cancel; )
	{
		// Check for available data.
		dwSize = 0;
		if(!WinHttpQueryDataAvailable(hRequest, &dwSize))
			throw new Exception("Error in WinHttpQueryDataAvailable:" ~ to!string(GetLastError()));
		if (dwSize <= 0)
			break;
		// Allocate space for the buffer.
		auto outBuffer = new char[dwSize+1];
		// Read the data.
		DWORD dwDownloaded = 0;
		if(!WinHttpReadData(hRequest, outBuffer.ptr, dwSize, &dwDownloaded))
			throw new Exception("Error in WinHttpReadData:" ~ to!string(GetLastError()));

		req.data ~= outBuffer[0..dwDownloaded];
	}
}

struct DownloadRequest
{
	const(wchar)* server;
	const(wchar)* request;
	ushort port = INTERNET_DEFAULT_HTTPS_PORT;
	bool done;
	bool error;
	bool cancel() { return updateCancelCounter != cancelCounter; }
	uint cancelCounter;
	string errorMessage;

	// to be filled by download
	DWORD fullSize;
	char[] data;
	Thread thread;
}

struct DownloadQueue
{
	DownloadRequest*[] requests;
}

private __gshared DownloadQueue downloadQueue;

DownloadRequest* startDownload(string url)
{
	ushort port = INTERNET_DEFAULT_HTTPS_PORT;
    auto i = indexOf(url, "://");
    if (i != -1)
    {
        if (icmp(url[0 .. i], "http") == 0)
			port = INTERNET_DEFAULT_HTTP_PORT;
		else if (icmp(url[0 .. i], "https") != 0)
			throw new Exception("http:// or https:// expected");
		url = url[i + 3 .. $];
    }

    i = indexOf(url, '/');
    string domain;

    if (i == -1)
    {
        domain = url;
        url    = "/";
    }
    else
    {
        domain = url[0 .. i];
        url    = url[i .. url.length];
    }

    i = indexOf(domain, ':');
    if (i != -1)
    {
        port   = to!ushort(domain[i + 1 .. domain.length]);
        domain = domain[0 .. i];
    }

    debug (HTMLGET)
        writefln("Connecting to %s on port %d...", domain, port);

	auto req = new DownloadRequest;

	req.server = toUTF16z(domain);
	req.request = toUTF16z(url);
	req.port = port;
	req.cancelCounter = updateCancelCounter;

	req.thread = new Thread(() {
		try
		{
			winHttpGet(req);
			req.done = true;
		}
		catch(Exception e)
		{
			req.error = true;
			req.errorMessage = e.message.idup;
		}
	}).start();

	return req;
}

extern(D) void runAsync(void delegate() exec, void delegate(string) dgMessage)
{
	new Thread(() {
		try
		{
			exec();
		}
		catch(Exception e)
		{
			dgMessage(e.msg);
		}
	}).start();
}

struct VersionInfo
{
	// break down major.minor.rev-suffix-sfxnum
	string major;
	string minor;
	string rev;
	string suffix;
	string sfxnum;
}

VersionInfo extractVersion(string verstr)
{
	import std.regex;
	try
	{
		__gshared static Regex!char re;
		if(re.empty)
			re = regex(`([0-9]+)\.([0-9]+)(\.([0-9]+))?([-\.]?([abr])?[a-z]*[-\.]?([0-9]*))?`);

		auto rematch = match(verstr, re);
		if (!rematch.empty)
		{
			auto captures = rematch.captures();
			VersionInfo info;
			info.major  = captures[1];
			info.minor  = captures[2];
			info.rev    = captures[4];
			info.suffix = captures[6];
			info.sfxnum = captures[7];
			return info;
		}
	}
	catch(Exception e)
	{
	}
	return VersionInfo(verstr);
}

string approxBytes(long bytes)
{
	import std.conv;
	if (bytes < (1L << 10))
		return to!string(bytes) ~ " Bytes";
	int scale = 0;
	if (bytes < (1L << 20))
		scale = 1;
	else if (bytes < (1L << 30))
		scale = 2;
	else
		scale = 3;
	static string[3] postfix = [ " kB", " MB", " GB" ];
	import std.format;
	string txt = format("%.*f", scale, cast(double) bytes / (1L << (scale * 10)));
	return txt ~ postfix[scale - 1];
}

void doUpdate(string baseDir, CheckProduct prod, int frequency, void delegate(string) dgProgress)
{
	if (auto info = checkForUpdate(prod, -1.days, frequency))
	{
		runAsync(() {
			string name = baseName(info.download_url);
			string downloadDir = buildPath(baseDir, "Downloads");
			string tgtfile = buildPath(downloadDir, name);
			if (!std.file.exists(tgtfile))
			{
				dgProgress("Downloading " ~ name);
				auto req = startDownload(info.download_url);
				while (!req.error && !req.done)
				{
					if (req.data.length == 0)
					{
						dgProgress(name ~ ": connecting");
					}
					else
					{
						import std.conv;
						string allbytes = req.fullSize > 0 ? " of " ~ approxBytes(req.fullSize) : "";
						dgProgress(name ~ ": " ~ approxBytes(req.data.length) ~ allbytes);
					}
					Thread.sleep(500.msecs);
				}
				req.thread.join();
				dgProgress(name ~ (req.cancel ? ": download cancelled" :
				                   req.error ? ": Error: " ~ req.errorMessage : ": downloaded"));
				if (!req.done || req.error || req.cancel)
					return;

				if (!std.file.exists(downloadDir))
					mkdirRecurse(downloadDir);
				std.file.write(tgtfile, req.data);
			}
			switch(prod)
			{
				case CheckProduct.VisualD:
					dgProgress("Installing Visual D: Please close all instances of Visual Studio!");
					ShellExecute(null, null, toUTF16z(tgtfile), null, null, SW_SHOW);
					break;

				case CheckProduct.DMD:
					string prgdir = buildPath(baseDir, "DMD");
					string dmd2x = buildPath(prgdir, info.name.replace(" ", "").toLower());
					if (!std.file.exists(dmd2x))
					{
						dgProgress("Installing to " ~ prgdir);
						if (!std.file.exists(prgdir))
							mkdirRecurse(prgdir);
						string zip = buildPath(Package.GetGlobalOptions().VisualDInstallDir, "7z", "7za.exe");
						string opts = `x "-o` ~ prgdir ~ `" -y "` ~ tgtfile ~ `"`;

						SHELLEXECUTEINFOW exinfo;
						exinfo.cbSize = exinfo.sizeof;
						exinfo.fMask = SEE_MASK_NOCLOSEPROCESS;
						exinfo.lpFile = toUTF16z(zip);
						exinfo.lpParameters = toUTF16z(opts);
						exinfo.nShow = SW_SHOW;
						if (!ShellExecuteEx(&exinfo))
							throw new Exception("Failed to execute " ~ zip);

						HRESULT hr = WaitForSingleObject(exinfo.hProcess, 60000);
						if (hr != WAIT_OBJECT_0)
							throw new Exception("Failed to extract " ~ tgtfile);
						string dmd2 = buildPath(prgdir, "dmd2");
						std.file.rename(dmd2, dmd2x);
					}
					Package.GetGlobalOptions().DMD.InstallDir = dmd2x;
					dgProgress("Switched to " ~ dmd2x);
					break;

				case CheckProduct.LDC:
					string prgdir = buildPath(baseDir, "LDC");
					string ldc2x = buildPath(prgdir, stripExtension(name));
					if (!std.file.exists(ldc2x))
					{
						dgProgress("Installing to " ~ prgdir);
						if (!std.file.exists(prgdir))
							mkdirRecurse(prgdir);
						string zip = buildPath(Package.GetGlobalOptions().VisualDInstallDir, "7z", "7za.exe");
						string opts = `x "-o` ~ prgdir ~ `" -y "` ~ tgtfile ~ `"`;

						SHELLEXECUTEINFOW exinfo;
						exinfo.cbSize = exinfo.sizeof;
						exinfo.fMask = SEE_MASK_NOCLOSEPROCESS;
						exinfo.lpFile = toUTF16z(zip);
						exinfo.lpParameters = toUTF16z(opts);
						exinfo.nShow = SW_SHOW;
						if (!ShellExecuteEx(&exinfo))
							throw new Exception("Failed to execute " ~ zip);

						HRESULT hr = WaitForSingleObject(exinfo.hProcess, 60000);
						if (hr != WAIT_OBJECT_0)
							throw new Exception("Failed to extract " ~ tgtfile);
					}
					Package.GetGlobalOptions().LDC.InstallDir = ldc2x;
					dgProgress("Switched to " ~ ldc2x);
					break;
				default:
					break;
			}
		}, dgProgress);
	}
}

version(TEST_UPDATE)
{
	void main(string[] args)
	{
		// checkForUpdate(CheckProduct.DMD, 0.seconds, false);
		auto req = startDownload(args[1]);
		req.thread.join();
		if (req.error)
			writeln("Error", req.errorMessage);
		else
			writeln("Success");
	}
}
