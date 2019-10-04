// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver.semanalysis;

import vdc.dmdserver.dmdinit;
import vdc.dmdserver.dmderrors;
import vdc.dmdserver.semvisitor;
import vdc.ivdserver;

import dmd.arraytypes;
import dmd.cond;
import dmd.dmodule;
import dmd.dsymbolsem;
import dmd.errors;
import dmd.globals;
import dmd.identifier;
import dmd.semantic2;
import dmd.semantic3;

__gshared AnalysisContext lastContext;

struct ModuleInfo
{
	Module parsedModule;
	Module semanticModule;

	Module createSemanticModule()
	{
		Module m = cloneModule(parsedModule);
		m.importedFrom = m;
		m.resolvePackage(); // adds module to Module.amodules (ignore return which could be module with same name)
		semanticModule = m;
		Module.modules.insert(m);
		return m;
	}
}

// context is kept as long as the options don't change
class AnalysisContext
{
	Options options;

	ModuleInfo[] modules;

	int findModuleInfo(Module parsedMod)
	{
		foreach (ref i, inf; modules)
			if (parsedMod is inf.parsedModule)
				return cast(int) i;
		return -1;
	}
	int findModuleInfo(const(char)[] filename)
	{
		foreach (ref i, inf; modules)
			if (filename == inf.parsedModule.srcfile.toString())
				return cast(int)i;
		return -1;
	}
}

// is the module already added implicitly during semantic analysis?
Module findInAllModules(const(char)[] filename)
{
	foreach(m; Module.amodules)
	{
		if (m.srcfile.toString() == filename)
			return m;
	}
	return null;
}

//
Module analyzeModule(Module parsedModule, const ref Options opts)
{
	int rootModuleIndex = -1;
	bool needsReinit = true;

	if (!lastContext)
		lastContext = new AnalysisContext;
	AnalysisContext ctxt = lastContext;

	auto filename = parsedModule.srcfile.toString();
	int idx = ctxt.findModuleInfo(filename);
	if (ctxt.options == opts)
	{
		if (idx >= 0)
		{
			if (parsedModule !is ctxt.modules[idx].parsedModule)
			{
				// module updated, replace it
				ctxt.modules[idx].parsedModule = parsedModule;

				// TODO: only update dependent modules
			}
			else
			{
				if (!ctxt.modules[idx].semanticModule)
				{
					auto m = ctxt.modules[rootModuleIndex].createSemanticModule();
					m.importAll(null);
				}
				needsReinit = false;
			}
			rootModuleIndex = idx;
		}
		else
		{
			ctxt.modules ~= ModuleInfo(parsedModule);
			rootModuleIndex = cast(int)(ctxt.modules.length - 1);

			// is the module already added implicitly during semantic analysis?
			auto ma = findInAllModules(filename);
			if (ma is null)
			{
				// if not, no other module depends on it, so just append
				auto m = ctxt.modules[rootModuleIndex].createSemanticModule();
				m.importAll(null);
				needsReinit = false;
			}
			else
			{
				// TODO: check if the same as m
				auto m = ctxt.modules[rootModuleIndex].createSemanticModule();
				m.importAll(null);
				// TODO: only update dependent modules
			}
		}
	}
	else
	{
		ctxt.options = opts;
		dmdSetupParams(opts);

		if (idx >= 0)
		{
			ctxt.modules[idx].parsedModule = parsedModule;
			rootModuleIndex = idx;
		}
		else
		{
			ctxt.modules ~= ModuleInfo(parsedModule);
			rootModuleIndex = cast(int)(ctxt.modules.length - 1);
		}
	}

	Module.loadModuleHandler = (const ref Loc location, IdentifiersAtLoc* packages, Identifier ident)
	{
		// only called if module not found in Module.amodules
		return Module.loadFromFile(location, packages, ident);
	};

	if (needsReinit)
	{
		dmdReinit();

		foreach(ref mi; ctxt.modules)
		{
			mi.createSemanticModule();
		}

		foreach(ref mi; ctxt.modules)
		{
			mi.semanticModule.importAll(null);
		}
	}

	Module.rootModule = ctxt.modules[rootModuleIndex].semanticModule;
	Module.rootModule.dsymbolSemantic(null);
	Module.dprogress = 1;
	Module.runDeferredSemantic();
	Module.rootModule.semantic2(null);
	Module.runDeferredSemantic2();
	Module.rootModule.semantic3(null);
	Module.runDeferredSemantic3();

	return Module.rootModule;
}

////////////////////////////////////////////////////////////////
//version = traceGC;
import tracegc;
extern(Windows) void OutputDebugStringA(const(char)* lpOutputString);

string[] guessImportPaths()
{
	import std.file;

	if (std.file.exists(r"c:\s\d\dlang\druntime\import\object.d"))
		return [ r"c:\s\d\dlang\druntime\import", r"c:\s\d\dlang\phobos" ];
	if (std.file.exists(r"c:\s\d\rainers\druntime\import\object.d"))
		return [ r"c:\s\d\rainers\druntime\import", r"c:\s\d\rainers\phobos" ];
	return [ r"c:\d\dmd2\src\druntime\import", r"c:\s\d\rainers\src\phobos" ];
}

unittest
{
	import core.memory;

	dmdInit();

	Options opts;
	opts.predefineDefaultVersions = true;
	opts.x64 = true;
	opts.msvcrt = true;
	opts.importDirs = guessImportPaths();

	auto filename = "source.d";

	static void assert_equal(S, T)(S s, T t)
	{
		if (s == t)
			return;
		assert(false);
	}

	Module checkErrors(string src, string expected_err)
	{
		initErrorFile(filename);
		Module parsedModule = createModuleFromText(filename, src);
		assert(parsedModule);
		Module m = analyzeModule(parsedModule, opts);
		auto err = cast(string) gErrorMessages;
		assert_equal(err, expected_err);
		return m;
	}

	void checkTip(Module analyzedModule, int line, int col, string expected_tip)
	{
		string tip = findTip(analyzedModule, line, col, line, col + 1);
		assert_equal(tip, expected_tip);
	}

	void checkDefinition(Module analyzedModule, int line, int col, string expected_fname, int expected_line, int expected_col)
	{
		string file = findDefinition(analyzedModule, line, col);
		assert_equal(file, expected_fname);
		assert_equal(line, expected_line);
		assert_equal(col, expected_col);
	}

	void checkBinaryIsInLocations(string src, Loc[] locs)
	{
		initErrorFile(filename);
		Module parsedModule = createModuleFromText(filename, src);
		auto err = cast(string) gErrorMessages;
		assert(err == null);
		assert(parsedModule);
		Loc[] locdata = findBinaryIsInLocations(parsedModule);
		assert(locdata.length == locs.length);
	L_nextLoc:
		foreach(i; 0 .. locdata.length)
		{
			// not listed twice
			foreach(ref loc; locdata[i+1 .. $])
				assert(locdata[i].linnum != loc.linnum || locdata[i].charnum != loc.charnum);
			// found in results
			foreach(ref loc; locs)
				if(locdata[i].linnum == loc.linnum && locdata[i].charnum == loc.charnum)
					continue L_nextLoc;
			assert(false);
		}
	}

	void checkExpansions(Module analyzedModule, int line, int col, string tok, string[] expected)
	{
		import std.algorithm, std.array;
		string[] expansions = findExpansions(analyzedModule, line, col, tok);
		expansions.sort();
		expected.sort();
		assert_equal(expansions.length, expected.length);
		for (size_t i = 0; i < expansions.length; i++)
			assert_equal(expansions[i].split(':')[0], expected[i]);
	}

	void checkIdentifierTypes(Module analyzedModule, IdTypePos[][string] expected)
	{
		static void assert_equalPositions(IdTypePos[] s, IdTypePos[] t)
		{
			assert_equal(s.length, t.length);
			assert_equal(s[0].type, t[0].type);
			foreach (i; 1.. s.length)
				assert_equal(s[i], t[i]);
		}
		import std.algorithm, std.array, std.string;
		auto idtypes = findIdentifierTypes(analyzedModule);
		assert_equal(idtypes.length, expected.length);
		auto ids = idtypes.keys();
		ids.sort();
		foreach (i, id; ids)
			assert_equalPositions(idtypes[id], expected[id]);
	}

	static struct TextPos
	{
		int line;
		int column;
	}
	void checkReferences(Module analyzedModule, int line, int col, TextPos[] expected)
	{
		import std.algorithm, std.array, std.string;
		auto refs = findReferencesInModule(analyzedModule, line, col);
		assert_equal(refs.length, expected.length);
		for (size_t i = 0; i < refs.length; i++)
		{
			assert_equal(refs[i].loc.linnum, expected[i].line);
			assert_equal(refs[i].loc.charnum, expected[i].column);
		}
	}

	void dumpAST(Module mod)
	{
		import dmd.root.outbuffer;
		import dmd.hdrgen;
		auto buf = OutBuffer();
		buf.doindent = 1;
		moduleToBuffer(&buf, mod);

		OutputDebugStringA(buf.peekChars);
	}

	string source;
	source = q{
		int main()
		{
			return abc;
		}
	};
	Module m = checkErrors(source, "4,10,4,11:undefined identifier `abc`\n");

	version(traceGC)
	{
		wipeStack();
		GC.collect();
	}

	//_CrtDumpMemoryLeaks();
	version(traceGC)
		dumpGC();

	source = q{
		import std.stdio;
		int main(string[] args)
		{
			int xyz = 7;
			writeln(1, 2, 3);
			return xyz;
		}
	};

	for (int i = 0; i < 1; i++) // loop for testing GC leaks
	{
		m = checkErrors(source, "");

		version(traceGC)
		{
			wipeStack();
			GC.collect();

			//_CrtDumpMemoryLeaks();
			//dumpGC();
		}

		//core.memory.GC.Stats stats = GC.stats();
		//trace_printf("GC stats: %lld MB used, %lld MB free\n", cast(long)stats.usedSize >> 20, cast(long)stats.freeSize >> 20);

		version(traceGC)
			if (stats.usedSize > (200 << 20))
				dumpGC();
	}

	checkTip(m, 5, 8, "(local variable) int xyz");
	checkTip(m, 5, 10, "(local variable) int xyz");
	checkTip(m, 5, 11, "");
	checkTip(m, 6, 8, "void std.stdio.writeln!(int, int, int)(int _param_0, int _param_1, int _param_2) @safe");
	checkTip(m, 7, 11, "(local variable) int xyz");

	version(traceGC)
	{
		wipeStack();
		GC.collect();
	}

	checkDefinition(m, 7, 11, "source.d", 5, 8); // xyz

	//checkTypeIdentifiers(source);

	source =
	q{	module pkg.source;               // Line 1
		int main(in string[] args)
		in(args.length > 1) in{ assert(args.length > 1); }
		do {
			static if(is(typeof(args[0]) : string)) // Line 5
				if (args[0] is args[1]) {}
				else if (args[1] !is args[0]) {}

			int[string] aa;
			if (auto p = args[0] in aa)  // Line 10
				if (auto q = args[1] !in aa) {}
			return 0;
		}
		static if(is(bool))
			bool t = null is null;       // Line 15
		else
			bool f = 0 in [1:1];

		enum EE { E1 = 3, E2 }
		void foo()                       // Line 20
		{
			auto ee = EE.E1;
		}
		import core.cpuid : cpu_vendor = vendor, processor;
		import cpuid = core.cpuid;       // Line 25
		string cpu_info()
		{
			return cpu_vendor ~ " " ~ processor;
		}
	};
	checkBinaryIsInLocations(source, [Loc(null, 6, 17), Loc(null, 7, 23),
									  Loc(null, 10, 25), Loc(null, 11, 26),
									  Loc(null, 15, 18), Loc(null, 17, 15)]);

	m = checkErrors(source, "");

	checkTip(m,  2, 24, "(parameter) const(string[]) args"); // function arg
	checkTip(m,  3,  6, "(parameter) const(string[]) args"); // in contract
	checkTip(m,  3, 34, "(parameter) const(string[]) args"); // in contract
	checkTip(m,  5, 24, "(parameter) const(string[]) args"); // static if is typeof expression
	checkTip(m,  6, 10, "(parameter) const(string[]) args"); // if expression
	checkTip(m, 11, 21, "(parameter) const(string[]) args"); // !in expression

	checkTip(m, 19,  9, "(enum) pkg.source.EE"); // enum EE
	checkTip(m, 19, 13, "(enum value) pkg.source.EE.E1 = 3"); // enum E1
	checkTip(m, 19, 21, "(enum value) pkg.source.EE.E2 = 4"); // enum E2
	checkTip(m, 22, 14, "(enum) pkg.source.EE"); // enum EE
	checkTip(m, 22, 17, "(enum value) pkg.source.EE.E1 = 3"); // enum E1

	checkTip(m,  1,  9, "(package) pkg");
	checkTip(m,  1, 13, "(module) pkg.source");
	checkTip(m, 24, 10, "(package) core");
	checkTip(m, 24, 15, "(module) core.cpuid");
	checkTip(m, 24, 23, "(alias) pkg.source.cpu_vendor = string core.cpuid.vendor() pure nothrow @nogc @property @trusted");
	checkTip(m, 24, 36, "(alias) pkg.source.cpu_vendor = string core.cpuid.vendor() pure nothrow @nogc @property @trusted");
	checkTip(m, 24, 44, "(alias) pkg.source.processor = string core.cpuid.processor() pure nothrow @nogc @property @trusted");
	checkTip(m, 28, 11, "string core.cpuid.vendor() pure nothrow @nogc @property @trusted");

	source =
	q{                                   // Line 1
		struct S
		{
			int field1 = 3;
			static long stat1 = 7;       // Line 5
			int fun(int par) { return field1 + par; }
		}
		void foo()
		{
			S anS;                       // Line 10
			int x = anS.fun(1);
		}
		int fun(S s)
		{
			auto p = new S(1);           // Line 15
			auto seven = S.stat1;
			return s.field1;
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  2, 10, "(struct) source.S");
	checkTip(m,  4,  8, "(field) int source.S.field1");
	checkTip(m,  6,  8, "int source.S.fun(int par)");
	checkTip(m,  6, 16, "(parameter) int par");
	checkTip(m,  6, 30, "(field) int source.S.field1");
	checkTip(m,  6, 39, "(parameter) int par");

	checkTip(m, 10,  4, "(struct) source.S");
	checkTip(m, 10,  6, "(local variable) source.S anS");
	checkTip(m, 11, 12, "(local variable) source.S anS");
	checkTip(m, 11, 16, "int source.S.fun(int par)");

	checkTip(m, 13, 11, "(struct) source.S");
	checkTip(m, 16, 19, "(thread local variable) long source.S.stat1");
	checkTip(m, 16, 17, "(struct) source.S");

	checkDefinition(m, 11, 16, "source.d", 6, 8);  // fun
	checkDefinition(m, 15, 17, "source.d", 2, 10); // S

	source =
	q{                                   // Line 1
		class C
		{
			int field1 = 3;
			static long stat1 = 7;       // Line 5
			int fun(int par) { return field1 + par; }
		}
		void foo()
		{
			C aC = new C;                // Line 10
			int x = aC.fun(1);
		}
		int fun(C c)
		{
			auto p = new C();            // Line 15
			auto seven = C.stat1;
			return c.field1;
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  2,  9, "(class) source.C");
	checkTip(m,  4,  8, "(field) int source.C.field1");
	checkTip(m,  6,  8, "int source.C.fun(int par)");
	checkTip(m,  6, 16, "(parameter) int par");
	checkTip(m,  6, 30, "(field) int source.C.field1");
	checkTip(m,  6, 39, "(parameter) int par");

	checkTip(m, 10,  4, "(class) source.C");
	checkTip(m, 10, 15, "(class) source.C");
	checkTip(m, 10,  6, "(local variable) source.C aC");
	checkTip(m, 11, 12, "(local variable) source.C aC");
	checkTip(m, 11, 16, "int source.C.fun(int par)");

	checkTip(m, 13, 11, "(class) source.C");
	checkTip(m, 16, 19, "(thread local variable) long source.C.stat1");
	checkTip(m, 16, 17, "(class) source.C");

	checkDefinition(m, 11, 16, "source.d", 6, 8);  // fun
	checkDefinition(m, 15, 17, "source.d", 2, 9);  // C

	source =
	q{                                   // Line 1
		struct ST(T)
		{
			T f;
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  2, 10, "(struct) source.ST(T)");
	checkTip(m,  4,  4, "(unresolved type) T");
	checkTip(m,  4,  6, "T f");

	source =
	q{                                   // Line 1
		void foo()
		{
			int x = 1;
			try
			{
				x++;
			}
			catch(Exception e)
			{                            // Line 10
				auto err = cast(Error) e;
				Exception* pe = &e;
				throw new Error("unexpected");
			}
			finally
			{
				x = 0;
			}
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  9, 20, "(local variable) object.Exception e");
	checkTip(m,  9, 10, "(class) object.Exception");
	checkTip(m,  11, 21, "(class) object.Error");
	checkTip(m,  12, 5, "(class) object.Exception");

	source =
	q{                                   // Line 1
		struct S
		{
			int field1 = 1;
			int field2 = 2;              // Line 5
			int fun(int par) { return field1 + par; }
			int more = 3;
		}
		void foo()
		{                                // Line 10
			S anS;
			int x = anS.f(1);
			int y = anS.
		}
	};
	m = checkErrors(source,
		"14,2,14,3:identifier or `new` expected following `.`, not `}`\n" ~
		"14,2,14,3:semicolon expected, not `}`\n" ~
		"12,14,12,15:no property `f` for type `S`\n");
	//dumpAST(m);
	checkExpansions(m, 12, 16, "f", [ "field1", "field2", "fun" ]);
	checkExpansions(m, 13, 16, "", [ "field1", "field2", "fun", "more" ]);
	checkExpansions(m, 13, 13, "an", [ "anS" ]);

	source =
	q{                                   // Line 1
		struct S
		{
			int fun(int par) { return par; }
		}                                // Line 5
		void fun(int rec)
		{
			S anS;
			int x = anS.fun(1);
			if (rec)                     // Line 10
				fun(false);
		}
	};
	m = checkErrors(source, "");

	IdTypePos[][string] exp = [
		"S":   [ IdTypePos(TypeReferenceKind.Struct) ],
		"x":   [ IdTypePos(TypeReferenceKind.LocalVariable) ],
		"anS": [ IdTypePos(TypeReferenceKind.LocalVariable) ],
		"rec": [ IdTypePos(TypeReferenceKind.ParameterVariable) ],
		"par": [ IdTypePos(TypeReferenceKind.ParameterVariable) ],
		"fun": [ IdTypePos(TypeReferenceKind.Method),
		         IdTypePos(TypeReferenceKind.Function, 6, 8),
		         IdTypePos(TypeReferenceKind.Method, 9, 16),
		         IdTypePos(TypeReferenceKind.Function, 11, 5)],
	];
	checkIdentifierTypes(m, exp);

	source =
	q{                                   // Line 1
		struct S
		{
			int fun(int par) { return par; }
			int foo() { return fun(1); } // Line 5
		}
		void fun(int rec)
		{
			S anS;
			int x = anS.fun(1);          // Line 10
			if (rec) fun(false);
		}
	};
	m = checkErrors(source, "");

	checkReferences(m, 4, 8, [TextPos(4,8), TextPos(5, 23), TextPos(10, 16)]);

	// foreach lowered to for
	source = q{                          // Line 1
		import std.range;
		int fun(int rec)
		{
			int sum = 0;                 // Line 5
			foreach(i; iota(0, rec))
				sum += i;
			return sum;
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m, 6, 12, "(local variable) int i");
	checkTip(m, 7, 5, "(local variable) int sum");
	checkTip(m, 7, 12, "(local variable) int i");

	source = q{                          // Line 1
		enum TOK : ubyte
		{
			reserved,
			leftParentheses,             // Line 5
			rightParentheses,
		}
		void foo(TOK op)
		{
			if (op == TOK.leftParentheses) {}   // Line 10
		}
		class Base
		{
			this(TOK op, size_t sz) {}
		}                                // Line 15
		class LeftBase : Base
		{
			this()
			{
				super(TOK.leftParentheses, LeftBase.sizeof);// Line 20
			}
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m, 10,  8, "(parameter) source.TOK op");
	checkTip(m, 10, 14, "(enum) source.TOK");
	checkTip(m, 10, 18, "(enum value) source.TOK.leftParentheses = 1");
	checkTip(m, 20, 11, "(enum) source.TOK");
	checkTip(m, 20, 15, "(enum value) source.TOK.leftParentheses = 1");
	checkTip(m, 20, 32, "(class) source.LeftBase");
	//checkTip(m, 20, 41, "(constant) source.LeftBase.sizeof = 8");
}

unittest
{
	import core.memory;
	import std.path;
	import std.file;

	dmdInit();
	string srcdir = "dmd/src";

	Options opts;
	opts.predefineDefaultVersions = true;
	opts.x64 = true;
	opts.msvcrt = true;
	opts.importDirs = guessImportPaths() ~ srcdir;
	opts.stringImportDirs ~= srcdir ~ "/../res";
	opts.versionIds ~= "MARS";
	//opts.versionIds ~= "NoBackend";

	auto filename = std.path.buildPath(srcdir, "dmd/expressionsem.d");

	static void assert_equal(S, T)(S s, T t)
	{
		if (s == t)
			return;
		assert(false);
	}

	Module checkErrors(string src, string expected_err)
	{
		try
		{
			initErrorFile(filename);
			Module parsedModule = createModuleFromText(filename, src);
			assert(parsedModule);
			Module m = analyzeModule(parsedModule, opts);
			auto err = cast(string) gErrorMessages;
			assert_equal(err, expected_err);
			return m;
		}
		catch(Throwable t)
		{
			throw t;
		}
	}
	string source = cast(string)std.file.read(filename);
	Module m = checkErrors(source, "");
}

// https://issues.dlang.org/show_bug.cgi?id=20253
void dummy()
{
}
