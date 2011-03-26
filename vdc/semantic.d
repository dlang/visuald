// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module semantic;

import util;
import ast.mod;
import ast.node;
import parser.engine;

import std.exception;
import std.stdio;
import std.string;

class SemanticException : Exception
{
	this(string msg)
	{
		super(msg);
	}
}

void semanticError(string filename, ref const(TextPos) pos, string msg)
{
	write(filename);
	if(pos.line > 0)
		write("(", pos.line, ")");
	write(": ");
	writeln(msg);
}

void semanticError(ref const(TextPos) pos, string msg)
{
	string filename;
	if(Scope.current && Scope.current.mod)
		filename = Scope.current.mod.filename;
	else
		filename = "at global scope";
	semanticError(filename, pos, msg);
}

void semanticError(string msg)
{
	semanticError(TextPos(), msg);
}

void semanticError(string fname, string msg)
{
	semanticError(fname, TextPos(), msg);
}

alias Node Symbol;

class Scope
{
	Scope parent;
	
	Annotation annotations;
	Attribute attributes;
	Module mod;
	Symbol[][string] symbols;
	Import[] imports;
	
	static Scope current;
	
	Scope pushClone()
	{
		Scope sc = new Scope;
		sc.annotations = annotations;
		sc.attributes = attributes;
		sc.mod = mod;
		sc.parent = this;
		return current = sc;
	}
	Scope push(Scope sc)
	{
		sc.parent = this;
		return current = sc;
	}
	
	Scope pop()
	{
		return current = parent;
	}
	
	void addSymbol(string ident, Symbol s)
	{
		if(auto sym = ident in symbols)
			*sym ~= s;
		else
			symbols[ident] = [s];
	}
	
	void addImport(Import imp)
	{
		imports ~= imp;
	}
	
	Symbol[] search(string ident)
	{
		if(auto pn = ident in symbols)
			return *pn;
		
		Node[] syms;
		foreach(imp; imports)
		{
			syms ~= imp.search(this, ident);
		}
		return syms;
	}
	
	Node resolve(string ident, ref const(TextSpan) span)
	{
		Node[] n = search(ident);
		if(n.length == 0)
		{
			semanticError(span.start, "unknown identifier " ~ ident);
			return null;
		}
		foreach(s; n)
			s.semanticSearches++;
		
		if(n.length > 1)
			semanticError(span.start, "ambiguous identifier " ~ ident);
		return n[0];
	}
	
	Project getProject() { return mod ? mod.getProject() : null; }
}

class Project : Node
{
	Options options;

	Module[string] mModulesByName;
	
	this()
	{
		super(TextSpan());
		options = new Options;
		options.importDirs ~= r"c:\s\d\phobos\druntime\import\";
		options.importDirs ~= r"c:\s\d\phobos\phobos\";
	}
	
	////////////////////////////////////////////////////////////
	Module addFile(string fname, bool imported = false)
	{
		debug writeln(fname, ":");
		Parser p = new Parser;
		Node n;
		try
		{
			string txt = readUtf8(fname);
			p.filename = fname;
			n = p.parseText(txt);
		}
		catch(Exception e)
		{
			writeln(e.msg);
			return null;
		}
		if(!n)
			return null;

		auto mod = static_cast!(Module)(n);
		mod.filename = fname;
		mod.imported = imported;
		
		string modname = mod.getModuleName();
		if(auto pm = modname in mModulesByName)
		{
			semanticError(fname, "module name " ~ modname ~ " already used by " ~ pm.filename);
			return null;
		}

		addMember(mod);
		mModulesByName[modname] = mod;
		return mod;
	}
	
	Module getModule(string modname)
	{
		if(auto pm = modname in mModulesByName)
			return *pm;
		return null;
	}

	Module importModule(string modname)
	{
		if(auto mod = getModule(modname))
			return mod;
		
		string dfile = replace(modname, ".", "/") ~ ".di";
		string srcfile = searchImportFile(dfile);
		if(srcfile.length == 0)
		{
			dfile = replace(modname, ".", "/") ~ ".d";
			srcfile = searchImportFile(dfile);
		}
		if(srcfile.length == 0)
		{
			semanticError("cannot find imported module " ~ modname);
			return null;
		}
		return addFile(srcfile, true);
	}
	
	string searchImportFile(string dfile)
	{
		if(std.file.exists(dfile))
			return dfile;
		foreach(dir; options.importDirs)
			if(std.file.exists(dir ~ dfile))
				return dir ~ dfile;
		return null;
	}
	
	void semantic()
	{
		Scope sc = new Scope;
		for(int m = 0; m < members.length; m++)
			members[m].semantic(sc);
	}

	////////////////////////////////////////////////////////////
	void writeCpp(string fname)
	{
		string src;
		CCodeWriter writer = new CCodeWriter(getStringSink(src));
		writer.writeDeclarations    = true;
		writer.writeImplementations = false;

		for(int m = 0; m < members.length; m++)
		{
			writer.writeReferencedOnly = getMember!Module(m).imported;
			writer(members[m]);
			writer.nl;
		}
		
		writer.writeDeclarations    = false;
		writer.writeImplementations = true;
		for(int m = 0; m < members.length; m++)
		{
			writer.writeReferencedOnly = getMember!Module(m).imported;
			writer(members[m]);
			writer.nl;
		}

		Node mainNode;
		for(int m = 0; m < members.length; m++)
			if(members[m].scop)
			{
				if(auto pn = "main" in members[m].scop.symbols)
				{
					if(pn.length > 1 || mainNode)
						semanticError("multiple candidates for main function");
					else
						mainNode = (*pn)[0];
				}
			}
		if(mainNode)
		{
			writer("int main(int argc, char**argv)");
			writer.nl;
			writer("{");
			writer.nl;
			{
				CodeIndenter indent = CodeIndenter(writer);
				Module mod = Module.getModule(mainNode);
				mod.writeNamespace(writer);
				writer("main();");
				writer.nl;
				writer("return 0;");
				writer.nl;
			}
			writer("}");
			writer.nl;
		}
		
		std.file.write(fname, src);
	}
	
	void toD(CodeWriter writer)
	{
		throw new SemanticException("Project.toD not implemeted");
	}
}

struct VersionInfo
{
	TextPos defined;     // line -1 if not defined yet
	TextPos firstUsage;  // line int.max if not used yet
}

struct VersionDebug
{
	int level;
	VersionInfo[string] identifiers;
	
	bool defined(string ident, TextPos pos)
	{
		if(auto vi = ident in identifiers)
		{
			if(pos < vi.defined)
				semanticError(pos, "identifier " ~ ident ~ " used before defined");

			if(pos < vi.firstUsage)
				vi.firstUsage = pos;

			return vi.defined.line >= 0;
		}
		VersionInfo vi;
		vi.defined.line = -1;
		vi.firstUsage = pos;
		identifiers[ident] = vi;
		return false;
	}
	
	void define(string ident, TextPos pos)
	{
		if(auto vi = ident in identifiers)
		{
			if(pos > vi.firstUsage)
				semanticError(pos, "identifier " ~ ident ~ " defined after usage");
			if(pos < vi.defined)
				vi.defined = pos;
		}
		
		VersionInfo vi;
		vi.firstUsage.line = int.max;
		vi.defined = pos;
		identifiers[ident] = vi;
	}
}

class Options
{
	bool unittestOn;
	
	string[] importDirs;
	
	public /* debug & version handling */ {
	bool debugOn;
	VersionDebug debugIds;
	VersionDebug versionIds;

	bool versionEnabled(string ident)
	{
		int pre = versionPredefined(ident);
		if(pre == 0)
			return versionIds.defined(ident, TextPos());
		
		switch(ident)
		{
			case "unittest":
				return unittestOn;
			default:
				return pre > 0;
		}
	}
	
	bool versionEnabled(int level)
	{
		return level <= versionIds.level;
	}
	
	bool debugEnabled(string ident)
	{
		return debugIds.defined(ident, TextPos());
	}

	bool debugEnabled(int level)
	{
		return level <= debugIds.level;
	}
	
	static int versionPredefined(string ident)
	{
		switch(ident)
		{
			case "DigitalMars":     return 1;
			case "X86":             return 1;
			case "X86_64":          return -1;
			case "Windows":         return 1;
			case "Win32":           return 1;
			case "Win64":           return -1;
			case "linux":           return -1;
			case "Posix":           return -1;
			case "LittleEndian":    return 1;
			case "BigEndian":       return -1;
			case "D_Coverage":      return -1;
			case "D_Ddoc":          return -1;
			case "D_InlineAsm_X86": return 1;
			case "D_InlineAsm_X86_64": return -1;
			case "D_LP64":          return -1;
			case "D_PIC":           return -1;
			case "unittest":        return -1;
			case "D_Version2":      return 1;
			case "none":            return -1;
			case "all":             return 1;
			default:                return 0;
		}
	}
	}
}

