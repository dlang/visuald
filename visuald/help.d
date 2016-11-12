// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.help;

import visuald.fileutil;
import visuald.dpackage;
import visuald.pkgutil;
import visuald.hierutil;
import visuald.comutil;

import dte2 = sdk.vsi.dte80;

import stdext.path;

import std.file;
import std.path;
import std.string;
import std.utf;
import std.uri;
import std.conv;
import std.array;

//////////////////////////////////////////////////////////////////////
static string[][string] tags;
alias AssociativeArray!(string, string[]) _wa1; // fully instantiate type info

static bool[string] searchAnchors(string file)
{
	bool[string] names;

	string s = to!string(std.file.read(file));
fulltext:
	for(size_t pos = 0; pos < s.length; )
	{
		dchar ch = decode(s, pos);
		if(ch == '<')
		{
			if(s[pos..$].startsWith("a name=\""))
			{
				auto p = s[pos+8..$].indexOf('\"');
				if(p < 0)
					break fulltext;
				string name = s[pos+8 .. pos+8 + p];
				names[name] = true;
				pos += 8 + p + 1;
			}
			while(ch != '>' && pos < s.length)
			{
				ch = decode(s, pos);
				if(ch == '\"')
				{
					auto p = s[pos..$].indexOf('\"');
					if(p < 0)
						break fulltext;
					pos += p + 1;
				}
			}
		}
		else if(ch == '\"')
		{
			auto p = s[pos..$].indexOf('\"');
			if(p < 0)
				break fulltext;
			pos += p + 1;
		}
	}
	return names;
}

void loadTags()
{
	string installdir = normalizeDir(Package.GetGlobalOptions().DMD.InstallDir) ~ "html/d/";
	if(!std.file.exists(installdir ~ "index.html"))
	{
		writeToBuildOutputPane("no documentation found at " ~ installdir);
		return;
	}
	tags = tags.init;
	foreach(string file; dirEntries(installdir, SpanMode.depth))
	{
		try
		{
			string bname = baseName(file);
			if(globMatch(bname, "*.html"))
			{
				auto names = searchAnchors(file);
				foreach(name, b; names)
					tags[name] ~= file;
			}
		}
		catch(Exception e)
		{
			// bad file access, utf8 exception, etc
			writeToBuildOutputPane("failed to read " ~ file);
		}
	}
}

string replacePath(string s, string href, string path)
{
	string url = "file://" ~ replace(path, "\\", "/");
	string t;
	for( ; ; )
	{
		int pos = s.indexOf(href);
		if(pos < 0)
			break;
		t ~= s[0..pos + href.length];
		s = s[pos + href.length .. $];
		if(!s.startsWith("http:/"))
			t ~= url;
	}
	t ~= s;
	return t;
}

string replaceRef(string s, string path)
{
	s = replacePath(s, `href="`, path);
	s = replacePath(s, `src="`, path);
	return s;
}

string createDisambiguationPage(string word, string[] files)
{
	string installdir = normalizeDir(Package.GetGlobalOptions().DMD.InstallDir) ~ "html/d/";
	string fallback = `<html lang="en-US"><head></head><body class="hyphenate"><div id="content"></div>`
		~ `<div id="footernav"></div></body></html>`;
	string html = fallback;

	string idxfile = installdir ~ "index.html";
	if(std.file.exists(idxfile))
		html = to!string(std.file.read(idxfile));

	string start = `<div id="content">`;
	string footer = `<div id="footernav">`;
	int ps = html.indexOf(start);
	int pe = html.indexOf(footer);
	if(ps < 0 || pe < ps)
	{
		html = fallback;
		ps = html.indexOf(start);
		pe = html.indexOf(footer);
	}
	string gen = "<p>There are multiple pages commenting on &quot;" ~ word ~ "&quot;</p><ul>\n";
	foreach(f; files)
	{
		string url = std.uri.encode("file://" ~ replace(f, "\\", "/") ~ "#" ~ word);
		string name = replace(stripExtension(baseName(f)), "_", ".");
		gen ~= `<li><a href="` ~ url ~ `">` ~ name ~ "</a></li>\n";
	}
	gen ~= "</ul>";
	string beg = replaceRef(html[0..ps + start.length], installdir);
	string end = replaceRef(html[pe..$], installdir);
	string nhtml = beg ~ gen ~ "</div>" ~ end;

	wchar[MAX_PATH] path;
	uint len = GetTempPath(MAX_PATH, path.ptr);
	string fname = normalizeDir(to_string(path.ptr, len)) ~ "vd_disambiguation.html";
	std.file.write(fname, nhtml);
	return fname;
}

bool openHelp(string word)
{
	static bool triedLoad;
	if(!triedLoad) // (tags.length == 0) no longer works ;-((
	{
		triedLoad = true;
		loadTags();
	}

	string url;
	auto files = word in tags;

	void tryAlternative(string alt)
	{
		if(!files)
		{
			files = alt in tags;
			if(files)
				word = alt;
		}
	}
	tryAlternative(capitalize(word) ~ "Statement");
	tryAlternative(capitalize(word) ~ "Declaration");
	tryAlternative(capitalize(word) ~ "Expression");
	if(word == "unittest") tryAlternative("UnitTest");
	if(word == "function" || word == "delegate") tryAlternative("closures");
	if(word == "__traits" || word == "traits") tryAlternative("TraitsExpression");

	if(files)
	{
		string file;
		if((*files).length == 1)
			file = (*files)[0] ~ "#" ~ word;
		else
			file = createDisambiguationPage(word, *files);
		url = std.uri.encode("file://" ~ replace(file, "\\", "/"));
	}

	if(url.length == 0)
		return false;

	if(dte2.DTE2 spvsDTE = GetDTE())
	{
		scope(exit) release(spvsDTE);
		spvsDTE.ExecuteCommand("View.WebBrowser"w.ptr, _toUTF16z(url));
	}
	return true;
}
