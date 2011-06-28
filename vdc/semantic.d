// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.semantic;

import vdc.util;
import vdc.ast.mod;
import vdc.ast.node;
import vdc.ast.type;
import vdc.ast.aggr;
import vdc.ast.decl;
import vdc.parser.engine;
import vdc.logger;
import vdc.interpret;

import std.exception;
import std.stdio;
import std.string;
import std.array;

int semanticErrors;

class SemanticException : Exception
{
	this(string msg)
	{
		super(msg);
	}
}

class InterpretException : Exception
{
	this()
	{
		super("cannot interpret");
	}
}

void semanticErrorWriteLoc(string filename, ref const(TextPos) pos)
{
	write(filename);
	if(pos.line > 0)
		write("(", pos.line, ")");
	write(": ");
	semanticErrors++;
}

void semanticErrorLoc(T...)(string filename, ref const(TextPos) pos, T args)
{
	foreach(a; args)
		if(typeid(a) == typeid(ErrorType) || typeid(a) == typeid(ErrorValue))
			return;
	
	semanticErrorWriteLoc(filename, pos);
	writeln(args);
}

void semanticErrorPos(T...)(ref const(TextPos) pos, T args)
{
	string filename;
	if(Scope.current && Scope.current.mod)
		filename = Scope.current.mod.filename;
	else
		filename = "at global scope";
	semanticErrorLoc(filename, pos, args);
}

void semanticError(T...)(T args)
{
	semanticErrorPos(TextPos(), args);
}

void semanticErrorFile(T...)(string fname, T args)
{
	semanticErrorLoc(fname, TextPos(), args);
}

void semanticMessage(string msg)
{
	writeln(msg);
}

ErrorValue semanticErrorValue(T...)(T args)
{
	semanticErrorPos(TextPos(), args);
	throw new InterpretException;
	// return Singleton!(ErrorValue).get();
}

ErrorType semanticErrorType(T...)(T args)
{
	semanticErrorPos(TextPos(), args);
	return Singleton!(ErrorType).get();
}

alias Node Symbol;

class Context 
{
	Scope scop;
	Value[Node] vars;
	Context parent;

	this(Context p)
	{
		parent = p;
	}

	Value getThis()
	{
		if(parent)
			return parent.getThis();
		return null;
	}
	
	void setThis(Value v)
	{
		setValue(null, v);
	}
	
	Value getValue(Node n)
	{
		if(auto pn = n in vars)
			return *pn;
		if(parent)
			return parent.getValue(n);
		return null;
	}

	void setValue(Node n, Value v)
	{
		vars[n] = v;
	}
}

class AggrContext : Context
{
	AggrValue instance;

	this(Context p, AggrValue inst)
	{
		super(p);
		instance = inst;
	}
	
	override Value getThis()
	{
		if(auto t = cast(Class)instance.getType())
			return new ClassValue(t, static_cast!ClassInstanceValue (instance));
		return instance;
	}

	override Value getValue(Node n)
	{
		if(auto pn = n in vars)
			return *pn;
		if(auto decl = cast(Declarator) n)
			if(Value v = instance._interpretProperty(this, decl.ident))
				return v;
		if(parent)
			return parent.getValue(n);
		return null;
	}
}

Context nullContext;
AggrContext noThisContext;

Context globalContext;
Context threadContext;

class Scope
{
	Scope parent;
	
	Annotation annotations;
	Attribute attributes;
	Module mod;
	Node node;
	Symbol[][string] symbols;
	Import[] imports;
	
	Context ctx; // compile time only
	
	static Scope current;
	
	enum
	{
		SearchParentScope = 1,
		SearchPrivateImport = 2,
	}
	
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
		if(!sc)
			return pushClone();

		sc.parent = this;
		return current = sc;
	}
	
	Scope pop()
	{
		return current = parent;
	}
	
	void addSymbol(string ident, Symbol s)
	{
		logInfo("Scope(%s).addSymbol(%s, sym %s=%s)", cast(void*)this, ident, s, cast(void*)s);
		
		if(auto sym = ident in symbols)
			*sym ~= s;
		else
			symbols[ident] = [s];
	}
	
	void addImport(Import imp)
	{
		imports ~= imp;
	}
	
	Symbol[] search(string ident, bool inParents, bool privateImports)
	{
		if(auto pn = ident in symbols)
			return *pn;
		
		Node[] syms;
		foreach(imp; imports)
		{
			if(privateImports || (imp.getProtection() & Annotation_Public))
				syms ~= imp.search(this, ident);
		}
		if(syms.length == 0 && inParents && parent)
			syms = parent.search(ident, true, privateImports);
		return syms;
	}

	Node resolveOverload(string ident, ref const(TextSpan) span, Node[] n)
	{
		if(n.length == 0)
		{
			semanticErrorPos(span.start, "unknown identifier " ~ ident);
			return null;
		}
		foreach(s; n)
			s.semanticSearches++;
		
		if(n.length > 1)
			semanticErrorPos(span.start, "ambiguous identifier " ~ ident);
		return n[0];
	}

	Node resolve(string ident, ref const(TextSpan) span, bool inParents = true)
	{
		Node[] n = search(ident, inParents, true);
		logInfo("Scope(%s).search(%s) found %s %s", cast(void*)this, ident, n, n.length > 0 ? cast(void*)n[0] : null);
		
		return resolveOverload(ident, span, n);
	}
	
	Project getProject() { return mod ? mod.getProject() : null; }
}

class Project : Node
{
	Options options;
	int countErrors;
	
	Module mObjectModule; // object.d
	Module[string] mModulesByName;
	
	this()
	{
		super(TextSpan());
		options = new Options;

		options.importDirs ~= r"c:\l\dmd-2.053\src\druntime\import\";
		options.importDirs ~= r"c:\l\dmd-2.053\src\phobos\";
		
		options.importDirs ~= r"c:\tmp\d\runnable\";
		
		globalContext = new Context(null);
		threadContext = new Context(null);
	}
	
	////////////////////////////////////////////////////////////
	Module addText(string fname, string txt, bool imported = false)
	{
		Parser p = new Parser;
		p.filename = fname;
		Node n;
		try
		{
			n = p.parseModule(txt);
		}
		catch(Exception e)
		{
			writeln(e.msg);
			countErrors += p.countErrors + 1;
			return null;
		}
		countErrors += p.countErrors;
		if(!n)
			return null;

		auto mod = static_cast!(Module)(n);
		mod.filename = fname;
		mod.imported = imported;
		
		string modname = mod.getModuleName();
		if(auto pm = modname in mModulesByName)
		{
			semanticErrorFile(fname, "module name " ~ modname ~ " already used by " ~ pm.filename);
			countErrors++;
			return null;
		}

		addMember(mod);
		mModulesByName[modname] = mod;
		return mod;
	}
	
	Module addFile(string fname, bool imported = false)
	{
		debug writeln(fname, ":");
		string txt = readUtf8(fname);
		return addText(fname, txt, imported);
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
		mObjectModule = importModule("object");

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
				Module mod = mainNode.getModule();
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
	
	override void toD(CodeWriter writer)
	{
		throw new SemanticException("Project.toD not implemeted");
	}
	
	int run()
	{
		Node[] funcs;
		foreach(m; mModulesByName)
			funcs ~= m.search("main");
		if(funcs.length == 0)
		{
			semanticError("no function main");
			return -1;
		}
		if(funcs.length > 1)
		{
			semanticError("multiple functions main");
			return -2;
		}
		TupleValue args = new TupleValue;
		try
		{
			Value v = funcs[0].interpret(nullContext).opCall(nullContext, args);
			if(v is theVoidValue)
				return 0;
			return v.toInt();
		}
		catch(InterpretException)
		{
			semanticError("cannot run main, interpretation aborted");
			return -1;
		}
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
				semanticErrorPos(pos, "identifier " ~ ident ~ " used before defined");

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
				semanticErrorPos(pos, "identifier " ~ ident ~ " defined after usage");
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

