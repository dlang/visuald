// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.lexutil;

import std.exception;
import std.stdio;

import visuald.fileutil;

import vdc.lexer;

string getModuleDeclarationName(string fname)
{
	string modname;
	try
	{
		enum ParseState { kSpace, kModule, kIdent, kDot }
		ParseState pstate = ParseState.kSpace;
		Lexer lex;
		int state = 0;
		File file = File(fname, "r");
		while(!file.eof())
		{
			string line = file.readln(); // File.byLine is unusable due to struct destructors not called (file never closed)
			uint pos = 0;
			while(pos < line.length)
			{
				int id;
				uint prevpos = pos;
				lex.scan(state, line, pos, id);
				if(id == TOK_Space || id == TOK_Comment)
					continue;
				
				final switch(pstate)
				{
					case ParseState.kSpace:
						if(id != TOK_module)
							return "";
						pstate = ParseState.kModule;
						break;
					case ParseState.kModule:
						if(id != TOK_Identifier)
							return "";
						modname = line[prevpos .. pos].idup;
						pstate = ParseState.kIdent;
						break;
					case ParseState.kIdent:
						if(id != TOK_dot)
							return modname;
						pstate = ParseState.kDot;
						break;
					case ParseState.kDot:
						if(id != TOK_Identifier)
							return modname;
						modname ~= "." ~ line[prevpos .. pos];
						pstate = ParseState.kIdent;
						break;
				}
			}
		}
		return "";
	}
	catch(Exception)
	{
		// not a valid file
		return "";
	}
}

