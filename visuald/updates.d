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
import visuald.pkgutil;

import std.conv;
import std.datetime;
import std.exception;
import std.file;
import std.json;
import std.path;
import std.process;
import std.string;
import std.utf;
import core.thread;

// version = HTTP_CALLBACK; // install status callback to debug failures

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
	GDC,
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
	try
	{
		auto info = _checkForUpdate(prod, renew, frequency);

		if (prod == CheckProduct.DMD && frequency == CheckFrequency.DailyPrereleases)
		{
			// check releases for DMD prerelases, too
			auto relinfo = _checkForUpdate(prod, renew, CheckFrequency.Daily);
			auto prever = extractVersion(info.name);
			auto relver = extractVersion(relinfo.name);
			if (relver > prever)
				info = relinfo;
		}
		return info;
	}
	catch(Exception e)
	{
		showStatusBarText("error while checking for update: " ~ e.msg);
	}
	return null;
}

UpdateInfo* _checkForUpdate(CheckProduct prod, Duration renew, int frequency)
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
		auto verinfo = extractVersion(txt);
		auto ver = verinfo.major ~ "." ~ verinfo.minor ~ "." ~ verinfo.rev;
		info.download_url = "http://" ~ domain ~ url[0..$-6] ~ verinfo.major ~ ".x/" ~ ver ~ "/dmd." ~ txt ~ ".windows.7z";
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
			string bdurl = asset["browser_download_url"].str();
			bool isDownload = prod == CheckProduct.LDC ? bdurl.indexOf("windows-multilib") >= 0
				: bdurl.endsWith(".exe") && bdurl.indexOf("dmd") < 0; // not the full package
			if (isDownload)
			{
				auto info = new UpdateInfo;
				info.name = r["name"].str();
				info.published = r["published_at"].str()[0..10]; // remove time
				info.download_url = bdurl;
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

	// Install the status callback function.
	version(HTTP_CALLBACK)
	auto isCallback = WinHttpSetStatusCallback(hSession, &winhttpStatusCallback,
											   WINHTTP_CALLBACK_FLAG_ALL_NOTIFICATIONS, 0);

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
			auto firstline = lines.length == 0 ? ""w : strip(lines[0]);
			if (!firstline.startsWith("HTTP/"))
				throw new Exception("no HTTP header");
			if (!firstline.endsWith(" OK") && !firstline.endsWith(" 200"))
				throw new Exception("unexpected answer: " ~ to!string(firstline));

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

	int opCmp(const VersionInfo rhs) const
	{
		int toNum(string s)
		{
			if (!s.empty)
				try return to!int(s);
				catch(Exception) {}

			return 0;
		}

		if (major != rhs.major)
			return toNum(major) < toNum(rhs.major) ? -1 : 1;
		if (minor != rhs.minor)
			return toNum(minor) < toNum(rhs.minor) ? -1 : 1;
		if (rev != rhs.rev)
			return toNum(rev) < toNum(rhs.rev) ? -1 : 1;
		if (suffix != rhs.suffix)
			return  suffix.empty ? 1 : // no suffix is better than "beta" or "rc"
				rhs.suffix.empty ? -1 : suffix < rhs.suffix ? -1 : 1;
		if (sfxnum != rhs.sfxnum)
			return toNum(sfxnum) < toNum(rhs.sfxnum) ? -1 : 1;
		return 0;
	}
}

VersionInfo extractVersion(string verstr)
{
	import std.regex;
	try
	{
		__gshared static Regex!char re;
		synchronized
		{
			if (re.empty)
				re = regex(`([0-9]+)\.([0-9]+)(\.([0-9]+))?([-\.]?([abr])?[a-z]*[-\.]?([0-9]*))?`);
		}
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
						dgProgress("Downloading " ~ name ~ ": connecting");
					}
					else
					{
						import std.conv;
						string allbytes = req.fullSize > 0 ? " of " ~ approxBytes(req.fullSize) : "";
						dgProgress("Downloading " ~ name ~ ": " ~ approxBytes(req.data.length) ~ allbytes);
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

			void unzipCompiler(string zipfile, string zipfolder, string tgtdir)
			{
				if (!std.file.exists(tgtdir))
				{
					dgProgress("Installing to " ~ tgtdir);
					string tmpdir = buildPath(baseDir, "__tmp");
					if (!std.file.exists(tmpdir))
						mkdirRecurse(tmpdir);
					string zip = buildPath(Package.GetGlobalOptions().VisualDInstallDir, "7z", "7za.exe");
					string opts = `x "-o` ~ tmpdir ~ `" -y "` ~ zipfile ~ `"`;

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
						throw new Exception("Failed to extract " ~ zipfile);

					string srcdir = buildPath(tmpdir, zipfolder);
					if (!std.file.exists(srcdir))
						throw new Exception("Unexpected zip file layout: " ~ zipfile);
					std.file.rename(srcdir, tgtdir);
					collectException(std.file.rmdir(tmpdir)); // only if empty
				}
				dgProgress("Switched to " ~ tgtdir);
			}

			switch(prod)
			{
				case CheckProduct.VisualD:
					dgProgress("Installing Visual D: Please close all instances of Visual Studio!");
					ShellExecute(null, null, toUTF16z(tgtfile), null, null, SW_SHOW);
					break;

				case CheckProduct.DMD:
					string dmdname = info.name.replace(" ", "-").toLower();
					string dmd2x = buildPath(baseDir, dmdname);
					unzipCompiler(tgtfile, "dmd2", dmd2x);
					Package.GetGlobalOptions().DMD.InstallDir = dmd2x;
					break;

				case CheckProduct.LDC:
					string ldcname = stripExtension(name);
					string ldc2x = buildPath(baseDir, stripExtension(name));
					unzipCompiler(tgtfile, ldcname, ldc2x);
					Package.GetGlobalOptions().LDC.InstallDir = ldc2x;
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

// Win7 SP1 might fail with "The application experienced an internal error loading the SSL libraries."
// Solution: enable TLS 1.1 and 1.2:
// https://support.microsoft.com/en-us/help/3140245/update-to-enable-tls-1-1-and-tls-1-2-as-default-secure-protocols-in-wi

version(HTTP_CALLBACK):
extern(Windows)
int winhttpStatusCallback(HINTERNET hInternet,
						  DWORD_PTR dwContext,
						  DWORD dwInternetStatus,
						  LPVOID lpvStatusInformation,
						  DWORD dwStatusInformationLength)
{
    char[1024] szBuffer;
    WINHTTP_ASYNC_RESULT *pAR;

	//if (dwContext == 0)
	//{
	//    // this should not happen, but we are being defensive here
	//    return;
	//}

	szBuffer[0] = 0;

	// Create a string that reflects the status flag.
	switch (dwInternetStatus)
	{
		case WINHTTP_CALLBACK_STATUS_CLOSING_CONNECTION:
			//Closing the connection to the server.The lpvStatusInformation parameter is NULL.
			snprintf(szBuffer.ptr, szBuffer.length, "CLOSING_CONNECTION (%d)", dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_CONNECTED_TO_SERVER:
			//Successfully connected to the server. 
			//The lpvStatusInformation parameter contains a pointer to an LPWSTR that indicates the IP address of the server in dotted notation.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "CONNECTED_TO_SERVER (%S)",  cast(WCHAR *)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "CONNECTED_TO_SERVER (%d)",  dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_CONNECTING_TO_SERVER:
			//Connecting to the server.
			//The lpvStatusInformation parameter contains a pointer to an LPWSTR that indicates the IP address of the server in dotted notation.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "CONNECTING_TO_SERVER (%S)", cast(WCHAR *)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "CONNECTING_TO_SERVER (%d)",  dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_CONNECTION_CLOSED:
			//Successfully closed the connection to the server. The lpvStatusInformation parameter is NULL. 
			snprintf(szBuffer.ptr, szBuffer.length, "CONNECTION_CLOSED (%d)",  dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_DATA_AVAILABLE:
			//Data is available to be retrieved with WinHttpReadData.The lpvStatusInformation parameter points to a DWORD that contains the number of bytes of data available.
			//The dwStatusInformationLength parameter itself is 4 (the size of a DWORD).

			snprintf(szBuffer.ptr, szBuffer.length, "DATA_AVAILABLE Number of bytes available : %d. All data has been read -> Displaying the data.", *cast(LPDWORD)lpvStatusInformation);
			break;

		case WINHTTP_CALLBACK_STATUS_HANDLE_CREATED:
			//An HINTERNET handle has been created. The lpvStatusInformation parameter contains a pointer to the HINTERNET handle.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "HANDLE_CREATED : %X",  cast(uint)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "HANDLE_CREATED (%d)",  dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING:
			//This handle value has been terminated. The lpvStatusInformation parameter contains a pointer to the HINTERNET handle. There will be no more callbacks for this handle.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "HANDLE_CLOSING : %X",  cast(uint)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "HANDLE_CLOSING (%d)",  dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE:
			//The response header has been received and is available with WinHttpQueryHeaders. The lpvStatusInformation parameter is NULL.
			snprintf(szBuffer.ptr, szBuffer.length, "HEADERS_AVAILABLE (%d)",  dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_INTERMEDIATE_RESPONSE:
			//Received an intermediate (100 level) status code message from the server. 
			//The lpvStatusInformation parameter contains a pointer to a DWORD that indicates the status code.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "INTERMEDIATE_RESPONSE Status code : %d",  *cast(DWORD*)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "INTERMEDIATE_RESPONSE (%d)",  dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_NAME_RESOLVED:
			//Successfully found the IP address of the server. The lpvStatusInformation parameter contains a pointer to a LPWSTR that indicates the name that was resolved.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "NAME_RESOLVED : %S",  cast(WCHAR *)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "NAME_RESOLVED (%d)",  dwStatusInformationLength);
			}
			break;


		case WINHTTP_CALLBACK_STATUS_READ_COMPLETE:
			//Data was successfully read from the server. The lpvStatusInformation parameter contains a pointer to the buffer specified in the call to WinHttpReadData. 
			//The dwStatusInformationLength parameter contains the number of bytes read.
			//When used by WinHttpWebSocketReceive, the lpvStatusInformation parameter contains a pointer to a WINHTTP_WEB_SOCKET_STATUS structure, 
			//	and the dwStatusInformationLength parameter indicates the size of lpvStatusInformation.

			snprintf(szBuffer.ptr, szBuffer.length, "READ_COMPLETE Number of bytes read : %d", dwStatusInformationLength);

			// Copy the data and delete the buffers.
			break;


		case WINHTTP_CALLBACK_STATUS_RECEIVING_RESPONSE:
			//Waiting for the server to respond to a request. The lpvStatusInformation parameter is NULL. 
			snprintf(szBuffer.ptr, szBuffer.length, "RECEIVING_RESPONSE (%d)", dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_REDIRECT:
			//An HTTP request is about to automatically redirect the request. The lpvStatusInformation parameter contains a pointer to an LPWSTR indicating the new URL.
			//At this point, the application can read any data returned by the server with the redirect response and can query the response headers. It can also cancel the operation by closing the handle

			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "REDIRECT to %S", cast(WCHAR *)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "REDIRECT (%d)", dwStatusInformationLength);
			}		
			break;

		case WINHTTP_CALLBACK_STATUS_REQUEST_ERROR:
			//An error occurred while sending an HTTP request. 
			//The lpvStatusInformation parameter contains a pointer to a WINHTTP_ASYNC_RESULT structure. Its dwResult member indicates the ID of the called function and dwError indicates the return value.
			pAR = cast(WINHTTP_ASYNC_RESULT *)lpvStatusInformation;
			snprintf(szBuffer.ptr, szBuffer.length, "REQUEST_ERROR - error %d, result %s",  pAR.dwError, "func".ptr /*GetApiErrorString(pAR.dwResult)*/);
			break;

		case WINHTTP_CALLBACK_STATUS_REQUEST_SENT:
			//Successfully sent the information request to the server. 
			//The lpvStatusInformation parameter contains a pointer to a DWORD indicating the number of bytes sent. 
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "REQUEST_SENT Number of bytes sent : %d", *cast(DWORD*)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "REQUEST_SENT (%d)", dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_RESOLVING_NAME:
			//Looking up the IP address of a server name. The lpvStatusInformation parameter contains a pointer to the server name being resolved.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "RESOLVING_NAME %S", cast(WCHAR*)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "RESOLVING_NAME (%d)", dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_RESPONSE_RECEIVED:
			//Successfully received a response from the server. 
			//The lpvStatusInformation parameter contains a pointer to a DWORD indicating the number of bytes received.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "RESPONSE_RECEIVED. Number of bytes : %d", *cast(DWORD*)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "RESPONSE_RECEIVED (%d)", dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_SECURE_FAILURE:
			//One or more errors were encountered while retrieving a Secure Sockets Layer (SSL) certificate from the server. 
			/*If the dwInternetStatus parameter is WINHTTP_CALLBACK_STATUS_SECURE_FAILURE, this parameter can be a bitwise-OR combination of one or more of the following values:
			WINHTTP_CALLBACK_STATUS_FLAG_CERT_REV_FAILED
			Certification revocation checking has been enabled, but the revocation check failed to verify whether a certificate has been revoked.The server used to check for revocation might be unreachable.
			WINHTTP_CALLBACK_STATUS_FLAG_INVALID_CERT
			SSL certificate is invalid.
			WINHTTP_CALLBACK_STATUS_FLAG_CERT_REVOKED
			SSL certificate was revoked.
			WINHTTP_CALLBACK_STATUS_FLAG_INVALID_CA
			The function is unfamiliar with the Certificate Authority that generated the server's certificate.
			WINHTTP_CALLBACK_STATUS_FLAG_CERT_CN_INVALID
			SSL certificate common name(host name field) is incorrect, for example, if you entered www.microsoft.com and the common name on the certificate says www.msn.com.
			WINHTTP_CALLBACK_STATUS_FLAG_CERT_DATE_INVALID
			SSL certificate date that was received from the server is bad.The certificate is expired.
			WINHTTP_CALLBACK_STATUS_FLAG_SECURITY_CHANNEL_ERROR
			The application experienced an internal error loading the SSL libraries.
			*/
			if (lpvStatusInformation)
			{
				import core.stdc.string;
				snprintf(szBuffer.ptr, szBuffer.length, "SECURE_FAILURE (%d).", *cast(DWORD*)lpvStatusInformation);
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_CERT_REV_FAILED)  //1
				{
					strcat(szBuffer.ptr, "Revocation check failed to verify whether a certificate has been revoked.");
				}
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_INVALID_CERT)  //2
				{
					strcat(szBuffer.ptr, "SSL certificate is invalid.");
				}
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_CERT_REVOKED)  //4
				{
					strcat(szBuffer.ptr, "SSL certificate was revoked.");
				}
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_INVALID_CA)  //8
				{
					strcat(szBuffer.ptr, "The function is unfamiliar with the Certificate Authority that generated the server\'s certificate.");
				}
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_CERT_CN_INVALID)  //10
				{
					strcat(szBuffer.ptr, "SSL certificate common name(host name field) is incorrect");
				}
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_CERT_DATE_INVALID)  //20
				{
					strcat(szBuffer.ptr, "CSSL certificate date that was received from the server is bad.The certificate is expired.");
				}
				if (*cast(DWORD*)lpvStatusInformation & WINHTTP_CALLBACK_STATUS_FLAG_SECURITY_CHANNEL_ERROR)  //80000000
				{
					strcat(szBuffer.ptr, "The application experienced an internal error loading the SSL libraries.");
				}
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "SECURE_FAILURE (%d)", dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_SENDING_REQUEST:
			// Sending the information request to the server.The lpvStatusInformation parameter is NULL.
			snprintf(szBuffer.ptr, szBuffer.length, "SENDING_REQUEST (%d)", dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE:
			snprintf(szBuffer.ptr, szBuffer.length, "SENDREQUEST_COMPLETE (%d)", dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_WRITE_COMPLETE:
			//Data was successfully written to the server. The lpvStatusInformation parameter contains a pointer to a DWORD that indicates the number of bytes written.
			//When used by WinHttpWebSocketSend, the lpvStatusInformation parameter contains a pointer to a WINHTTP_WEB_SOCKET_STATUS structure, 
			//and the dwStatusInformationLength parameter indicates the size of lpvStatusInformation.
			if (lpvStatusInformation)
			{
				snprintf(szBuffer.ptr, szBuffer.length, "WRITE_COMPLETE (%d)", *cast(DWORD*)lpvStatusInformation);
			}
			else
			{
				snprintf(szBuffer.ptr, szBuffer.length, "WRITE_COMPLETE (%d)", dwStatusInformationLength);
			}
			break;

		case WINHTTP_CALLBACK_STATUS_GETPROXYFORURL_COMPLETE:
			// The operation initiated by a call to WinHttpGetProxyForUrlEx is complete. Data is available to be retrieved with WinHttpReadData.
			snprintf(szBuffer.ptr, szBuffer.length, "GETPROXYFORURL_COMPLETE (%d)", dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_CLOSE_COMPLETE:
			// The connection was successfully closed via a call to WinHttpWebSocketClose.
			snprintf(szBuffer.ptr, szBuffer.length, "CLOSE_COMPLETE (%d)", dwStatusInformationLength);
			break;

		case WINHTTP_CALLBACK_STATUS_SHUTDOWN_COMPLETE:
			// The connection was successfully shut down via a call to WinHttpWebSocketShutdown
			snprintf(szBuffer.ptr, szBuffer.length, "SHUTDOWN_COMPLETE (%d)", dwStatusInformationLength);
			break;

		default:
			snprintf(szBuffer.ptr, szBuffer.length, "Unknown/unhandled callback - status %d given", dwInternetStatus);
			break;
	}

	OutputDebugStringA(szBuffer.ptr);
	return 0;
}
