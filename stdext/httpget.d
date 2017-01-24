// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module stdext.httpget;

import std.string, std.conv, std.stdio;
import std.socket;
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
	SocketStream ss   = new SocketStream(sock);

	debug (HTMLGET)
		writefln("Connected! Requesting URL \"%s\"...", url);

	if (port != 80)
		domain = domain ~ ":" ~ to!string(port);

	string request = "GET " ~ url ~ " HTTP/1.0\r\n"
		~ "Host: " ~ domain ~ "\r\n";
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

	auto file = new std.stdio.File(dstfile, "w");
	scope(exit) file.close();

	auto bufSize = min(partial_length + 1, 65536);
	ubyte[] buf = new ubyte[bufSize];
	bool testLF = true; // switching from readLine to readBlock might leave a pending LF in the input stream

	ulong sumRead = 0;
	size_t read;
	while ((read = ss.readBlock(buf.ptr, bufSize)) > 0)
	{
		int skip = (testLF && buf[0] == '\n' ? 1 : 0);
		file.rawWrite(buf[skip..read]);
		testLF = false;
		sumRead += read - skip;
	}
	return sumRead;
}

// deprecated in phobos 2.069, so extract what's needed
class SocketStream
{
	private	Socket sock;

	this(Socket s)
	{
		sock = s;
	}

	/**
	* Attempts to read the entire block, waiting if necessary.
	*/
	size_t readBlock(void* _buffer, size_t size)
	{
		if (size == 0)
			return size;

		ubyte* buffer = cast(ubyte*)_buffer;
		auto len = sock.receive(buffer[0 .. size]);
		//readEOF = cast(bool)(len == 0);
		if (len == sock.ERROR)
			len = 0;
		return len;
	}

	// reads a line, terminated by either CR, LF, CR/LF, or EOF
	char[] readLine()
	{
		return readLine(null);
	}

	// reads a line, terminated by either CR, LF, CR/LF, or EOF
	// reusing the memory in buffer if result will fit and otherwise
	// allocates a new string
	char[] readLine(char[] result)
	{
		size_t strlen = 0;
		char ch = getc();
		while (true) {
			switch (ch) {
				case '\r':
					prevCr = true;
					goto case;
				case '\n':
				case char.init:
					result.length = strlen;
					return result;

				default:
					if (strlen < result.length) {
						result[strlen] = ch;
					} else {
						result ~= ch;
					}
					strlen++;
			}
			ch = getc();
		}
		result.length = strlen;
		return result;
	}

	// unget buffer
	private wchar[] unget;
	final bool ungetAvailable() { return unget.length > 1; }
	private bool prevCr = false;

	// reads and returns next character from the stream,
	// handles characters pushed back by ungetc()
	// returns char.init on eof.
	char getc()
	{
		char c;
		if (prevCr) {
			prevCr = false;
			c = getc();
			if (c != '\n')
				return c;
		}
		if (unget.length > 1) {
			c = cast(char)unget[unget.length - 1];
			unget.length = unget.length - 1;
		} else {
			readBlock(&c,1);
		}
		return c;
	}


	/**
	* Attempts to write the entire block, waiting if necessary.
	*/
	size_t writeBlock(const void* _buffer, size_t size)
	{
		if (size == 0)
			return size;

		ubyte* buffer = cast(ubyte*)_buffer;
		auto len = sock.send(buffer[0 .. size]);
		//readEOF = cast(bool)(len == 0);
		if (len == sock.ERROR)
			len = 0;
		return len;
	}

	// writes block of data of specified size,
	// throws WriteException on error
	void writeExact(const void* buffer, size_t size)
	{
		const(void)* p = buffer;
		for(;;) {
			if (!size) return;
			size_t writesize = writeBlock(p, size);
			if (writesize == 0) break;
			p += writesize;
			size -= writesize;
		}
		if (size != 0)
			throw new Exception("unable to write to stream");
	}

	// writes a string, throws WriteException on error
	void writeString(const(char)[] s)
	{
		writeExact(s.ptr, s.length);
	}
}
