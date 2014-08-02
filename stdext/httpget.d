// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module stdext.httpget;

import std.string, std.conv, std.stream, std.stdio;
import std.socket, std.socketstream;
import std.algorithm : min;

ulong httpget(string url, string dstfile, ulong partial_start = 0, ulong partial_length = ulong.max)
{
	auto i = indexOf(url, "://");
	if (i != -1)
	{
		if (icmp(url[0 .. i], "http"))
			throw new Exception("http:// expected");
		url = url[i + 3 .. $];
	}

	i = indexOf(url, '#');
	if (i != -1)    // Remove anchor ref.
		url = url[0 .. i];

	string domain;
	i = indexOf(url, '/');
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

	ushort port;
	i = indexOf(domain, ':');
	if (i == -1)
	{
		port = 80;         // Default HTTP port.
	}
	else
	{
		port   = to!ushort(domain[i + 1 .. domain.length]);
		domain = domain[0 .. i];
	}
	return httpget(domain, port, url, dstfile, partial_start, partial_length);
}

ulong httpget(string domain, ushort port, string url, string dstfile, ulong partial_start = 0, ulong partial_length = ulong.max)
{
	debug (HTMLGET)
		writefln("Connecting to %s on port %d...", domain, port);

	Socket sock = new TcpSocket(new InternetAddress(domain, port));
	scope(exit) sock.close();
	Stream ss   = new SocketStream(sock);

	debug (HTMLGET)
		writefln("Connected! Requesting URL \"%s\"...", url);

	if (port != 80)
		domain = domain ~ ":" ~ to!string(port);

	string request = "GET " ~ url ~ " HTTP/1.0\r\n"
		"Host: " ~ domain ~ "\r\n";
	if(partial_length < ulong.max)
	{
		string range = to!string(partial_start) ~ "-" ~ to!string(partial_start + partial_length - 1);
		request ~= "Range: bytes=" ~ range ~ "\r\n";
	}
	request ~= "\r\n";
	debug (HTMLGET)
		writeln("Request: ", request);
	ss.writeString(request);

	// Skip HTTP header.
	while (true)
	{
		auto line = ss.readLine();
		if (!line.length)
			break;
		debug (HTMLGET)
			writeln(line);
	}

	auto file = new std.stream.File(dstfile, FileMode.OutNew);
	scope(exit) file.close();

	auto bufSize = min(partial_length + 1, 65536);
	ubyte[] buf = new ubyte[bufSize];
	bool testLF = true; // switching from readLine to readBlock might leave a pending LF in the input stream

	ulong sumRead = 0;
	size_t read;
	while ((read = ss.readBlock(buf.ptr, bufSize)) > 0)
	{
		int skip = (testLF && buf[0] == '\n' ? 1 : 0);
		file.writeBlock(buf.ptr + skip, read - skip);
		testLF = false;
		sumRead += read - skip;
	}
	return sumRead;
}
