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

// debug version = traceGC;

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

		version(none) // do this lazily
		foreach(ref mi; ctxt.modules)
		{
			mi.semanticModule.importAll(null);
		}
	}

	Module.rootModule = ctxt.modules[rootModuleIndex].semanticModule;
	Module.rootModule.importAll(null);
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
version (traceGC) import tracegc;

extern(C) int _CrtDumpMemoryLeaks();
extern(C) void dumpGC();
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
	version(traceGC)
	{
		import core.memory;
		import std.stdio;
		GC.collect();
		writeln(GC.stats);
		dumpGC();

		do_unittests();

		writeln(GC.stats);

		lastContext = null;
		dmdInit();
		dmdReinit();

		wipeStack();
		GC.collect();
		auto stats = GC.stats;
		writeln(stats);
		//if (stats.usedSize > 2_000_000)
			dumpGC();
	}
	else
		do_unittests();
}

void do_unittests()
{
	import core.memory;

	dmdInit();
	dmdReinit();
	lastContext = null;

	Options opts;
	opts.predefineDefaultVersions = true;
	opts.x64 = true;
	opts.msvcrt = true;
	opts.warnings = true;
	opts.noDeprecated = true;
	opts.unittestOn = true;
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
		initErrorMessages(filename);
		Module parsedModule = createModuleFromText(filename, src);
		assert(parsedModule);
		Module m = analyzeModule(parsedModule, opts);
		auto err = getErrorMessages();
		auto other = getErrorMessages(true);
		assert_equal(err, expected_err);
		assert_equal(other, "");
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
		initErrorMessages(filename);
		Module parsedModule = createModuleFromText(filename, src);
		auto err = getErrorMessages();
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
	Module m;
	source = q{
		int main()
		{
			return abc;
		}
	};
	m = checkErrors(source, "4,10,4,11:Error: undefined identifier `abc`\n");

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

		version(none)
		version(traceGC)
		{
			wipeStack();
			GC.collect();

			//_CrtDumpMemoryLeaks();
			//dumpGC();

			core.memory.GC.Stats stats = GC.stats();
			trace_printf("GC stats: %lld MB used, %lld MB free\n", cast(long)stats.usedSize >> 20, cast(long)stats.freeSize >> 20);

			if (stats.usedSize > (200 << 20))
				dumpGC();
		}
	}

	checkTip(m, 5, 8, "(local variable) `int xyz`");
	checkTip(m, 5, 10, "(local variable) `int xyz`");
	checkTip(m, 6, 4, "`void std.stdio.writeln!(int, int, int)(int _param_0, int _param_1, int _param_2) @safe`");
	checkTip(m, 5, 11, "");
	checkTip(m, 6, 8, "`void std.stdio.writeln!(int, int, int)(int _param_0, int _param_1, int _param_2) @safe`");
	checkTip(m, 7, 11, "(local variable) `int xyz`");

	checkDefinition(m, 7, 11, "source.d", 5, 8); // xyz

	//checkTypeIdentifiers(source);

	source =
	q{	module pkg.source;               // Line 1
		int main(in string[] args)
		in(args.length > 1) in{ assert(args.length > 1); }
		do {
			static if(is(typeof(args[0]) : string)) { // Line 5
				if (args[0] is args[1]) {}
				else if (args[1] !is args[0]) {}
			}
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

	checkTip(m,  2, 24, "(parameter) `const(string[]) args`"); // function arg
	checkTip(m,  3,  6, "(parameter) `const(string[]) args`"); // in contract
	checkTip(m,  3, 34, "(parameter) `const(string[]) args`"); // in contract
	checkTip(m,  5, 24, "(parameter) `const(string[]) args`"); // static if is typeof expression
	checkTip(m,  6, 10, "(parameter) `const(string[]) args`"); // if expression
	checkTip(m, 11, 21, "(parameter) `const(string[]) args`"); // !in expression

	checkTip(m, 10, 13, "(local variable) `int* p`");
	checkTip(m, 10, 17, "(parameter) `const(string[]) args`"); // in expression
	checkTip(m, 10, 28, "(local variable) `int[string] aa`");

	checkReferences(m, 10, 13, [TextPos(10,13)]); // p

	checkTip(m, 19,  9, "(enum) `pkg.source.EE`"); // enum EE
	checkTip(m, 19, 13, "(enum value) `pkg.source.EE.E1 = 3`"); // enum E1
	checkTip(m, 19, 21, "(enum value) `pkg.source.EE.E2 = 4`"); // enum E2
	checkTip(m, 22, 14, "(enum) `pkg.source.EE`"); // enum EE
	checkTip(m, 22, 17, "(enum value) `pkg.source.EE.E1 = 3`"); // enum E1

	checkTip(m,  1,  9, "(package) `pkg`");
	checkTip(m,  1, 13, "(module) `pkg.source`");
	checkTip(m, 24, 10, "(package) `core`");
	checkTip(m, 24, 15, "(module) `core.cpuid`");
	checkTip(m, 24, 23, "(alias) `pkg.source.cpu_vendor = string core.cpuid.vendor() pure nothrow @nogc @property @trusted`");
	checkTip(m, 24, 36, "(alias) `pkg.source.cpu_vendor = string core.cpuid.vendor() pure nothrow @nogc @property @trusted`");
	checkTip(m, 24, 44, "(alias) `pkg.source.processor = string core.cpuid.processor() pure nothrow @nogc @property @trusted`");
	checkTip(m, 28, 11, "`string core.cpuid.vendor() pure nothrow @nogc @property @trusted`");

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

	checkTip(m,  2, 10, "(struct) `source.S`");
	checkTip(m,  4,  8, "(field) `int source.S.field1`");
	checkTip(m,  6,  8, "`int source.S.fun(int par)`");
	checkTip(m,  6, 16, "(parameter) `int par`");
	checkTip(m,  6, 30, "(field) `int source.S.field1`");
	checkTip(m,  6, 39, "(parameter) `int par`");

	checkTip(m, 10,  4, "(struct) `source.S`");
	checkTip(m, 10,  6, "(local variable) `source.S anS`");
	checkTip(m, 11, 12, "(local variable) `source.S anS`");
	checkTip(m, 11, 16, "`int source.S.fun(int par)`");

	checkTip(m, 13, 11, "(struct) `source.S`");
	checkTip(m, 16, 19, "(thread local global) `long source.S.stat1`");
	checkTip(m, 16, 17, "(struct) `source.S`");

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

	checkTip(m,  2,  9, "(class) `source.C`");
	checkTip(m,  4,  8, "(field) `int source.C.field1`");
	checkTip(m,  6,  8, "`int source.C.fun(int par)`");
	checkTip(m,  6, 16, "(parameter) `int par`");
	checkTip(m,  6, 30, "(field) `int source.C.field1`");
	checkTip(m,  6, 39, "(parameter) `int par`");

	checkTip(m, 10,  4, "(class) `source.C`");
	checkTip(m, 10, 15, "(class) `source.C`");
	checkTip(m, 10,  6, "(local variable) `source.C aC`");
	checkTip(m, 11, 12, "(local variable) `source.C aC`");
	checkTip(m, 11, 16, "`int source.C.fun(int par)`");

	checkTip(m, 13, 11, "(class) `source.C`");
	checkTip(m, 16, 19, "(thread local global) `long source.C.stat1`");
	checkTip(m, 16, 17, "(class) `source.C`");

	checkDefinition(m, 11, 16, "source.d", 6, 8);  // fun
	checkDefinition(m, 15, 17, "source.d", 2, 9);  // C

	// enum value
	source =
	q{                                   // Line 1
		enum TTT = 9;
		void fun(int y = TTT)
		{
			int x = TTT;                // Line 5
			static assert(msg.length == 4);
		}
		static assert(TTT == 9, msg);   // compiler doesn't analyze the msg if the assert passes
		enum msg = "fail";
	};
	m = checkErrors(source, "");

	checkTip(m,  2,  8, "(constant) `int source.TTT = 9`");
	checkTip(m,  5, 13, "(constant) `int source.TTT = 9`");
	checkTip(m,  3, 20, "(constant) `int source.TTT = 9`");
	checkTip(m,  6, 18, "(constant) `string source.msg = \"fail\"`");
	checkTip(m,  6, 22, "(constant) `ulong \"fail\".length = 4LU`"); // string.length?
	checkTip(m,  8, 17, "(constant) `int source.TTT = 9`");
	checkTip(m,  8, 17, "(constant) `int source.TTT = 9`");
	checkTip(m,  9,  8, "(constant) `string source.msg = \"fail\"`");

	// template struct without instances
	source =
	q{                                   // Line 1
		struct ST(T)
		{
			T f;
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  2, 10, "(struct) `source.ST(T)`");
	checkTip(m,  4,  4, "(unresolved type) `T`");
	checkTip(m,  4,  6, "`T f`");

	source =
	q{                                   // Line 1
		inout(Exception) foo(inout(char)* ptr)
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
				const(Exception*) cpe = &e;
				throw new Error("unexpected");
			}                            // Line 15
			catch(Throwable)
			{}
			finally
			{
				x = 0;
			}
			return null;
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  9,  20, "(local variable) `object.Exception e`");
	checkTip(m,  9,  10, "(class) `object.Exception`");
	checkTip(m,  11, 21, "(class) `object.Error`");
	checkTip(m,  12,  5, "(class) `object.Exception`");
	checkTip(m,  13, 11, "(class) `object.Exception`");
	checkTip(m,   2,  9, "(class) `object.Exception`");
	checkTip(m,  16, 10, "(class) `object.Throwable`");

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
		"14,2,14,3:Error: identifier or `new` expected following `.`, not `}`\n" ~
		"14,2,14,3:Error: semicolon expected, not `}`\n" ~
		"12,15,12,16:Error: no property `f` for type `source.S`\n");
	//dumpAST(m);
	checkExpansions(m, 12, 16, "f", [ "field1", "field2", "fun" ]);
	checkExpansions(m, 13, 16, "", [ "field1", "field2", "fun", "more" ]);
	checkExpansions(m, 13, 13, "an", [ "anS" ]);

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
			if (anS.fool == 1) {}
		}
	};
	m = checkErrors(source,
					"12,11,12,12:Error: no property `fool` for type `source.S`\n");
	//dumpAST(m);
	checkExpansions(m, 12, 12, "f", [ "field1", "field2", "fun" ]);

	source =
	q{                                   // Line 1
		class C
		{
			int toDebug() { return 0; }
		}                                // Line 5
		void foo()
		{
			C c = new C;
			c.toString();
			if (c.toDebug()) {}          // Line 10
		}
	};
	m = checkErrors(source, "");
	checkExpansions(m,  9,  6, "to", [ "toString", "toHash", "toDebug" ]);
	checkExpansions(m, 10, 10, "to", [ "toString", "toHash", "toDebug" ]);

	source =
		q{                                   // Line 1
			class C
			{
				int toDebug() { return 0; }
			}                                // Line 5
			void foo()
			{
				C c = new C;
				if (c.to
			}                                // Line 10
		};
		m = checkErrors(source, "10,3,10,4:Error: found `}` when expecting `)`\n" ~
								"10,3,10,4:Error: found `}` instead of statement\n" ~
								"9,10,9,11:Error: no property `to` for type `source.C`, perhaps `import std.conv;` is needed?\n");
		dumpAST(m);
		checkExpansions(m,  9,  11, "to", [ "toString", "toHash", "toDebug" ]);

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

	// references
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

	checkReferences(m, 4, 8, [TextPos(4,8), TextPos(5, 23), TextPos(10, 16)]); // fun

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

	checkTip(m, 6, 12, "(local variable) `int i`");
	checkTip(m, 7, 5, "(local variable) `int sum`");
	checkTip(m, 7, 12, "(local variable) `int i`");

	source = q{                          // Line 1
		enum TOK : ubyte
		{
			reserved,
			leftParentheses,             // Line 5
			rightParentheses, /// right parent doc
		}
		void foo(TOK op)
		{
			if (op == TOK.leftParentheses) {}   // Line 10
		}
		class Base : Object
		{
			this(TOK op, size_t sz) {}
		}                                // Line 15
		/// right base doc
		class RightBase : Base
		{
			this()
			{                            // Line 20
				super(TOK.rightParentheses, RightBase.sizeof);
			}
		}
		TOK[Base] mapBaseTOK;

		c_long testcase(int op)
		{
			switch(op)
			{   // from object.d
				case TypeInfo_Class.ClassFlags.isCOMclass:       // Line 30
				case TypeInfo_Class.ClassFlags.noPointers:
				default:
					break;
			}
			return 0;
		}
		import core.stdc.config;
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m, 10,  8, "(parameter) `source.TOK op`");
	checkTip(m, 10, 14, "(enum) `source.TOK`");
	checkTip(m, 10, 18, "(enum value) `source.TOK.leftParentheses = 1`");
	checkTip(m, 21, 11, "(enum) `source.TOK`");
	checkTip(m, 21, 15, "(enum value) `source.TOK.rightParentheses = 2`");
	checkTip(m, 21, 33, "(class) `source.RightBase`\n\nright base doc");
	checkTip(m, 24, 19, "(thread local global) `source.TOK[source.Base] source.mapBaseTOK`");
	checkTip(m, 24,  7, "(class) `source.Base`");
	checkTip(m, 24,  3, "(enum) `source.TOK`");
	checkTip(m, 30, 10, "(class) `object.TypeInfo_Class`");
	checkTip(m, 30, 25, "(enum) `object.TypeInfo_Class.ClassFlags`");
	checkTip(m, 30, 36, "(enum value) `object.TypeInfo_Class.ClassFlags.isCOMclass = 1u`");
	checkTip(m, 21, 43, "(constant) `ulong source.RightBase.sizeof = 8LU`");

	IdTypePos[][string] exp2 = [
		"size_t":           [ IdTypePos(TypeReferenceKind.Alias) ],
		"Base":             [ IdTypePos(TypeReferenceKind.Class) ],
		"mapBaseTOK":       [ IdTypePos(TypeReferenceKind.TLSVariable) ],
		"TOK":              [ IdTypePos(TypeReferenceKind.Enum) ],
		"testcase":         [ IdTypePos(TypeReferenceKind.Function) ],
		"rightParentheses": [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"__ctor":           [ IdTypePos(TypeReferenceKind.Method) ],
		"sz":               [ IdTypePos(TypeReferenceKind.ParameterVariable) ],
		"RightBase":        [ IdTypePos(TypeReferenceKind.Class) ],
		"foo":              [ IdTypePos(TypeReferenceKind.Function) ],
		"leftParentheses":  [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"op":               [ IdTypePos(TypeReferenceKind.ParameterVariable) ],
		"reserved":         [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"noPointers":       [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"isCOMclass":       [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"TypeInfo_Class":   [ IdTypePos(TypeReferenceKind.Class) ],
		"ClassFlags":       [ IdTypePos(TypeReferenceKind.Enum) ],
		"Object":           [ IdTypePos(TypeReferenceKind.Class) ],
		"core":             [ IdTypePos(TypeReferenceKind.Package) ],
		"stdc":             [ IdTypePos(TypeReferenceKind.Package) ],
		"config":           [ IdTypePos(TypeReferenceKind.Module) ],
		"c_long":           [ IdTypePos(TypeReferenceKind.Alias) ],
		"sizeof":           [ IdTypePos(TypeReferenceKind.Constant) ],
	];
	checkIdentifierTypes(m, exp2);

	// string expressions with concat
	source = q{
		void fun()
		{
			string cmd = "cmd";
			bool isX86_64 = true;        // Line 5
			cmd = "pushd .\n" ~ `call vcvarsall.bat ` ~ (isX86_64 ? "amd64" : "x86") ~ "\n" ~ "popd\n" ~ cmd;
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  6, 49, "(local variable) `bool isX86_64`");
	checkTip(m,  6, 97, "(local variable) `string cmd`");

	// alias
	source = q{
		enum EE = 3;
		alias EE E1;
		alias E2 = EE;
		alias ET(T) = E1;   // Line 5
		alias ETint = ET!int;
		enum Enum { En1, En2 }
		alias En1 = Enum.En1;
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  2,  8, "(constant) `int source.EE = 3`");
	checkTip(m,  3,  9, "(constant) `int source.EE = 3`");
	checkTip(m,  3, 12, "(alias constant) `source.E1 = int source.EE = 3`");
	checkTip(m,  4,  9, "(alias constant) `source.E2 = int source.EE = 3`");
	checkTip(m,  4, 14, "(constant) `int source.EE = 3`");
	checkTip(m,  5,  9, "(alias constant) `source.ET!int = int source.EE = 3`");
	checkTip(m,  6,  9, "(alias constant) `source.ETint = int source.EE = 3`");

	checkReferences(m, 7, 15, [TextPos(7,15), TextPos(8, 20)]); // En1

	exp2 = [
		"EE":               [ IdTypePos(TypeReferenceKind.Constant) ],
		"E1":               [ IdTypePos(TypeReferenceKind.Alias) ],
		"E2":               [ IdTypePos(TypeReferenceKind.Alias) ],
		"ET":               [ IdTypePos(TypeReferenceKind.Alias) ],
		//"T":                [ IdTypePos(TypeReferenceKind.TemplateParameter) ],
		"ETint":            [ IdTypePos(TypeReferenceKind.Alias) ],
		"Enum":             [ IdTypePos(TypeReferenceKind.Enum) ],
		"En2":              [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"En1":              [ IdTypePos(TypeReferenceKind.EnumValue),
		                      IdTypePos(TypeReferenceKind.Alias, 8, 9),
		                      IdTypePos(TypeReferenceKind.EnumValue, 8, 20) ],
	];
	checkIdentifierTypes(m, exp2);

	source = q{
		int fun()
		{
			int sum;
			foreach(m; object.ModuleInfo)  // Line 5
				if (m) sum++;
			return sum;
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);
	checkTip(m,  6,  9, "(foreach variable) `object.ModuleInfo* m`");
	checkTip(m,  5, 12, "(foreach variable) `object.ModuleInfo* m`");
	checkTip(m,  5, 15, "(module) `object`");
	checkTip(m,  5, 22, "(struct) `object.ModuleInfo`");

	exp2 = [
		"fun":              [ IdTypePos(TypeReferenceKind.Function) ],
		"sum":              [ IdTypePos(TypeReferenceKind.LocalVariable) ],
		"m":                [ IdTypePos(TypeReferenceKind.ParameterVariable) ],
		"object":           [ IdTypePos(TypeReferenceKind.Module) ],
		"ModuleInfo":       [ IdTypePos(TypeReferenceKind.Struct) ],
	];
	checkIdentifierTypes(m, exp2);

	source = q{
		void fun()
		{
			string str = "hello";
			string cmd = ()     // Line 5
			{
				auto local = str.length;
				return str;
			}();
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  7, 10, "(local variable) `ulong local`");
	checkTip(m,  7, 18, "(local variable) `string str`");

	source = q{
		struct S(T)
		{
			T member;
		}                              // Line 5
		S!int x;
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  6,  9, "(thread local global) `source.S!int source.x`");
	checkTip(m,  4,  6, "(field) `int source.S!int.member`");
	checkTip(m,  6,  3, "(struct) `source.S!int`");

	// scope statement in version caused crash
	source = q{
		void fun(uint p)
		{
			switch (p)
			{                            // Line 5
				case 1:
					version(all)
					{
						{
							int x = 4;   // Line 10
							int y = 3;
						}
					}
					else
					{
						{
							int y = 3;
						}
					}
					break;
				default:
			}
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkReferences(m,  10, 12, [TextPos(10, 12)]); // x

	exp2 = [
		"all": [IdTypePos(TypeReferenceKind.VersionIdentifier)],
		"p":   [IdTypePos(TypeReferenceKind.ParameterVariable)],
		"y":   [IdTypePos(TypeReferenceKind.LocalVariable)],
		"fun": [IdTypePos(TypeReferenceKind.Function)],
		"x":   [IdTypePos(TypeReferenceKind.LocalVariable)],
	];
	checkIdentifierTypes(m, exp2);

	// check for conditional not producing warning "unreachable code"
	source = q{
		void foo()
		{
			version(none)
			{                          // Line 5
			}
			int test;
		}
	};
	m = checkErrors(source, "");

	source = q{
		static if(__traits(compiles, () { Object o = new Object; })) {}
		static if(!__traits(compiles, () { auto o = Object; })) {}
	};
	m = checkErrors(source, "");

	checkTip(m,  2, 37, "(class) `object.Object`");
	checkTip(m,  2, 44, "(local variable) `object.Object o`");
	checkTip(m,  3, 47, "(class) `object.Object`");

	// check for semantics in unittest
	source = q{
		unittest
		{
			int var1 = 1;
			int var2 = var1 + 1;       // Line 5
		}
	};
	m = checkErrors(source, "");
	checkTip(m,  5, 15, "(local variable) `int var1`");

	// check position of var in AddrExp
	source = q{
		void fun(int* p);
		void foo()
		{
			int var = 1;               // Line 5
			fun(&var);
		}
	};
	m = checkErrors(source, "");
	checkReferences(m, 5, 8, [TextPos(5,8), TextPos(6, 9)]); // var

	// check position of var in AddrExp
	source = q{
		struct S { int x = 3; }
		void fun(T)(T* p) {}
		void foo()
		{
			S var;               // Line 6
			fun!(S)(&var);
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  7,  9, "(struct) `source.S`");

	// float properties
	source = q{
		float flt;
		auto q = [flt.sizeof, flt.init, flt.epsilon, flt.mant_dig,
				  flt.infinity, flt.min_normal, flt.min_10_exp, flt.min_exp,
				  flt.max_10_exp, flt.max_exp]; // Line 5
		float fre(cfloat f)
		{
			return f.re + f.im;
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  3, 17, "(constant) `ulong float.sizeof = 4LU`");
	checkTip(m,  3, 29, "(constant) `float float.init = nanF`");
	checkTip(m,  3, 39, "(constant) `float float.epsilon = 1.19209e-07F`");
	checkTip(m,  3, 52, "(constant) `int float.mant_dig = 24`");
	checkTip(m,  4, 11, "(constant) `float float.infinity = infF`");
	checkTip(m,  4, 25, "(constant) `float float.min_normal = 1.17549e-38F`");
	checkTip(m,  4, 41, "(constant) `int float.min_10_exp = -37`");
	checkTip(m,  4, 57, "(constant) `int float.min_exp = -125`");
	checkTip(m,  5, 11, "(constant) `int float.max_10_exp = 38`");
	checkTip(m,  5, 27, "(constant) `int float.max_exp = 128`");
	checkTip(m,  8, 13, "(field) `float cfloat.re`");
	checkTip(m,  8, 20, "(field) `float cfloat.im`");

	// check template arguments
	source = q{
		void fun(T)() {}
		void foo()
		{
			fun!(object.ModuleInfo)();  // Line 5
		}
	};
	m = checkErrors(source, "");

	checkTip(m,  5,  9, "(module) `object`");
	checkTip(m,  5, 16, "(struct) `object.ModuleInfo`");

	exp2 = [
		"fun":              [ IdTypePos(TypeReferenceKind.Function) ],
		"foo":              [ IdTypePos(TypeReferenceKind.Function) ],
		"object":           [ IdTypePos(TypeReferenceKind.Module) ],
		"ModuleInfo":       [ IdTypePos(TypeReferenceKind.Struct) ],
	];
	checkIdentifierTypes(m, exp2);

	// check template arguments
	source = q{
		template Templ(T)
		{
			struct S
			{                       // Line 5
				T payload;
			}
			enum value = 4;
		}
		void fun()                  // Line 10
		{
			Templ!(ModuleInfo).S arr;
			int v = Templ!Object.value;
		};
	};
	m = checkErrors(source, "");

	checkTip(m,  2, 12, "(template) `source.Templ(T)`");
	checkTip(m, 12,  4, "(template instance) `source.Templ!(object.ModuleInfo)`");
	checkTip(m, 12, 23, "(struct) `source.Templ!(object.ModuleInfo).S`");
	checkTip(m, 12, 11, "(struct) `object.ModuleInfo`");
	checkTip(m, 13, 12, "(template instance) `source.Templ!(object.Object)`");
	checkTip(m, 13, 18, "(class) `object.Object`");
	checkTip(m, 13, 25, "(constant) `int source.Templ!(object.Object).value = 4`");

	// check FQN types in cast
	source = q{
		void foo(Error*)
		{
			auto e = cast(object.Exception) null;
			auto p = cast(object.Exception*) null;  // Line 5
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  2, 12, "(class) `object.Error`");
	checkTip(m,  4, 18, "(module) `object`");
	checkTip(m,  4, 25, "(class) `object.Exception`");
	checkTip(m,  5, 18, "(module) `object`");
	checkTip(m,  5, 25, "(class) `object.Exception`");

	exp2 = [
		"foo":       [ IdTypePos(TypeReferenceKind.Function) ],
		"object":    [ IdTypePos(TypeReferenceKind.Module) ],
		"Exception": [ IdTypePos(TypeReferenceKind.Class) ],
		"e":         [ IdTypePos(TypeReferenceKind.LocalVariable) ],
		"p":         [ IdTypePos(TypeReferenceKind.LocalVariable) ],
		"Error":     [ IdTypePos(TypeReferenceKind.Class) ],
	];
	checkIdentifierTypes(m, exp2);

	// fqn, function call on static members
	source = q{
		struct Mem
		{
			static Mem foo(int sz) { return Mem(); }
			ref Mem func(ref Mem m);             // Line 5
		}
		__gshared Mem mem;
		void fun()
		{
			source.Mem m = source.mem.foo(1234); // Line 10
		}
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  5, 12, "`Mem source.Mem.func(ref Mem m) ref`"); // TDOO: ref after func?
	checkTip(m,  5,  8, "(struct) `source.Mem`");
	checkTip(m,  5, 21, "(struct) `source.Mem`");
	checkTip(m,  5, 25, "(parameter) `source.Mem m`");
	checkTip(m, 10, 30, "`Mem source.Mem.foo(int sz)`");
	checkTip(m, 10, 19, "(module) `source`");
	checkTip(m, 10, 26, "(__gshared global) `source.Mem source.mem`");
	checkTip(m, 10, 11, "(struct) `source.Mem`");
	checkTip(m, 10,  4, "(module) `source`");

	// UFCS
	source = q{
		int foo(Object o, int sz)
		{
			return sz * 2;
		}                            // Line 5
		int fun()
		{
			auto o = new Object;
			return o.    foo(4);
		}                            // Line 10
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  9, 11, "(local variable) `object.Object o`");
	checkTip(m,  9, 17, "`int source.foo(Object o, int sz)`");

	// FQN
	source = q{
		module pkg.pkg2.mod; static import pkg.pkg2.mod;
		void goo()
		{
			import pkg.pkg2.mod : poo = goo;   // Line 5
			pkg.pkg2.mod.goo();
			poo();
			pkg.pkg2.mod.tmpl(1);
		}
		void tmpl(T)(T t) {}              // Line 10
	};
	m = checkErrors(source, "");

	checkTip(m,  6, 17, "`void pkg.pkg2.mod.goo()`");
	checkTip(m,  6, 13, "(module) `pkg.pkg2.mod`");
	checkTip(m,  6,  4, "(package) `pkg`");
	checkTip(m,  8,  4, "(package) `pkg`");
	checkTip(m,  8, 13, "(module) `pkg.pkg2.mod`");

	checkReferences(m,  6, 17, [TextPos(3,  8), TextPos(5, 32), TextPos(6, 17), TextPos(7,  4)]); // goo/poo
	checkReferences(m, 10,  8, [TextPos(8, 17), TextPos(10, 8)]); // tmpl
	checkReferences(m,  6, 13, [TextPos(2, 19), TextPos(2, 47), TextPos(5, 20), TextPos(6, 13), TextPos(8, 13)]); // mod
	checkReferences(m,  6,  4, [TextPos(2, 10), TextPos(2, 38), TextPos(5, 11), TextPos(6,  4), TextPos(8,  4)]); // pkg

	// UDA
	source = q{
		struct uda {}
		@uda int x;
		void foo(@uda uint u);
	};
	m = checkErrors(source, "");
	//dumpAST(m);

	checkTip(m,  3, 12, "(thread local global) `int source.x`");
	checkTip(m,  3,  4, "(struct) `source.uda`");
	checkTip(m,  4, 13, "(struct) `source.uda`");

	checkReferences(m, 2, 10, [TextPos(2, 10), TextPos(3, 4), TextPos(4, 13)]); // uda

	// deprecation
	source = q{
		deprecated void dep() {}
		void foo()
		{
			dep();
			source.dep();
		}
	};
	m = checkErrors(source,
					"5,3,5,4:Deprecation: function `source.dep` is deprecated\n" ~
					"6,10,6,11:Deprecation: function `source.dep` is deprecated\n" ~
					"6,10,6,11:Deprecation: function `source.dep` is deprecated\n");
	//dumpAST(m);

	// type references
	source = q{
		void foo(Object ss)
		{
			auto o = cast(Object)ss;
			auto s = S!Object(new Object);  // Line 5
		}
		struct S(T)
		{
			T payload;
		}
	};
	m = checkErrors(source, "");

	checkReferences(m, 2, 12, [TextPos(2,12), TextPos(4, 18), TextPos(5, 26), TextPos(5, 15)]); // Object

	// no semantics after error
	source = q{
		int abc;
		void funky()
		{
			a = 1
			if (a == 1)
			{
			}
		}
	};
	m = checkErrors(source,
		"6,3,6,4:Error: found `if` when expecting `;` following statement\n" ~
		"6,9,6,10:Error: found `==` when expecting `)`\n" ~
		"6,12,6,13:Error: missing `{ ... }` for function literal\n" ~
		"6,12,6,13:Error: found `1` when expecting `;` following statement\n" ~
		"6,13,6,14:Error: found `)` instead of statement\n" ~
		"9,2,9,3:Error: unrecognized declaration\n" ~
		"5,3,5,4:Error: undefined identifier `a`\n" ~
		"6,6,6,7:Error: undefined identifier `a`\n");

	exp2 = [
		"abc":             [ IdTypePos(TypeReferenceKind.TLSVariable) ],
		"funky":           [ IdTypePos(TypeReferenceKind.Function) ],
	];
	checkIdentifierTypes(m, exp2);

	///////////////////////////////////////////////////////////
	// check array initializer
	filename = "tok.d";
	source = q{
		module tok;
		enum TOK : ubyte
		{
			reserved,

			// Other
			leftParentheses,
			rightParentheses,
			max_
		}
		enum PREC : int
		{
			zero,
			expr,
		}
	};
	m = checkErrors(source, "");
	source = q{
		import tok;
		immutable PREC[TOK.max_] precedence =
		[
			TOK.reserved : PREC.zero,             // Line 5
			TOK.leftParentheses : PREC.expr,
		];
	};
	filename = "source.d";
	m = checkErrors(source, "");

	// TODO: checkTip(m, 3, 18, "(enum) `tok.TOK`");
	checkTip(m, 3, 22, "(enum value) `tok.TOK.max_ = 3`");
	checkTip(m, 3, 13, "(enum) `tok.PREC`");
	checkTip(m, 5,  4, "(enum) `tok.TOK`");
	checkTip(m, 5,  8, "(enum value) `tok.TOK.reserved = cast(ubyte)0u`");
	checkTip(m, 5, 19, "(enum) `tok.PREC`");
	checkTip(m, 5, 24, "(enum value) `tok.PREC.zero = 0`");

	IdTypePos[][string] exp4 = [
		"tok":             [ IdTypePos(TypeReferenceKind.Package) ],
		"zero":            [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"expr":            [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"reserved":        [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"leftParentheses": [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"max_":            [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"PREC":            [ IdTypePos(TypeReferenceKind.Enum) ],
		"TOK":             [ IdTypePos(TypeReferenceKind.Enum) ],
		"precedence":      [ IdTypePos(TypeReferenceKind.GSharedVariable) ],
	];
	checkIdentifierTypes(m, exp4);

	source = q{
		int[] darr = [ TypeInfo_Class.ClassFlags.isCOMclass ];
		int[int] aarr =
		[
			TypeInfo_Class.ClassFlags.isCOMclass : 1,  // Line 5
			1 : TypeInfo_Class.ClassFlags.isCOMclass
		];
		int[] iarr = [ TypeInfo_Class.ClassFlags.noPointers : 1 ];
		void fun()
		{                                              // Line 10
			auto a = darr.length + aarr.length;
			auto p = darr.ptr;
		}
	};
	m = checkErrors(source, "");
	checkTip(m,  2, 18, "(class) `object.TypeInfo_Class`");
	checkTip(m,  2, 33, "(enum) `object.TypeInfo_Class.ClassFlags`");
	checkTip(m,  2, 44, "(enum value) `object.TypeInfo_Class.ClassFlags.isCOMclass = 1u`");
	checkTip(m,  5, 4, "(class) `object.TypeInfo_Class`");
	checkTip(m,  5, 19, "(enum) `object.TypeInfo_Class.ClassFlags`");
	checkTip(m,  5, 30, "(enum value) `object.TypeInfo_Class.ClassFlags.isCOMclass = 1u`");
	checkTip(m,  6, 8, "(class) `object.TypeInfo_Class`");
	checkTip(m,  6, 23, "(enum) `object.TypeInfo_Class.ClassFlags`");
	checkTip(m,  6, 34, "(enum value) `object.TypeInfo_Class.ClassFlags.isCOMclass = 1u`");
	checkTip(m,  8, 18, "(class) `object.TypeInfo_Class`");
	checkTip(m,  8, 33, "(enum) `object.TypeInfo_Class.ClassFlags`");
	checkTip(m,  8, 44, "(enum value) `object.TypeInfo_Class.ClassFlags.noPointers = 2u`");
	checkTip(m, 11, 18, "(field) `ulong int[].length`");
	checkTip(m, 11, 32, "(field) `ulong int[int].length`");
	checkTip(m, 12, 18, "(field) `int* int[].ptr`");

	checkReferences(m, 2, 44, [TextPos(2,44), TextPos(5, 30), TextPos(6, 34)]); // isCOMclass

	IdTypePos[][string] exp3 = [
		"isCOMclass":       [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"noPointers":       [ IdTypePos(TypeReferenceKind.EnumValue) ],
		"TypeInfo_Class":   [ IdTypePos(TypeReferenceKind.Class) ],
		"ClassFlags":       [ IdTypePos(TypeReferenceKind.Enum) ],
		"darr":             [ IdTypePos(TypeReferenceKind.TLSVariable) ],
		"aarr":             [ IdTypePos(TypeReferenceKind.TLSVariable) ],
		"iarr":             [ IdTypePos(TypeReferenceKind.TLSVariable) ],
		"fun":              [ IdTypePos(TypeReferenceKind.Function) ],
		"length":           [ IdTypePos(TypeReferenceKind.MemberVariable) ],
		"ptr":              [ IdTypePos(TypeReferenceKind.MemberVariable) ],
		"a":                [ IdTypePos(TypeReferenceKind.LocalVariable) ],
		"p":                [ IdTypePos(TypeReferenceKind.LocalVariable) ],
	];
	checkIdentifierTypes(m, exp3);

	// more than 7 cases translated to table
	source = q{
		bool isReserved(const(char)[] ident)
		{
			// more than 7 cases use dup
			switch (ident)
			{
				case "DigitalMars":
				case "GNU":
				case "LDC":
				case "SDC":
				case "Windows":
				case "Win32":
				case "Win64":
				case "linux":
				case "OSX":
				case "iOS":
				case "TVOS":
				case "WatchOS":
				case "FreeBSD":
				case "OpenBSD":
				case "NetBSD":
				case "DragonFlyBSD":
				case "BSD":
				case "Solaris":
					return true;
				default:
					return false;
			}
		}
	};
	m = checkErrors(source, "");

	// change settings to restart everything
	opts.unittestOn = false;
	filename = "source2.d";
	m = checkErrors(source, "");

	// can object.d create reserved classes, e.g. Error?
	source = q{
		module object;
		alias ulong size_t;
		class Object
		{
		}
		class Throwable
		{
		}
		class Error : Throwable
		{
		}
	};
	m = checkErrors(source, "");
	// beware: bad object.d after this point
	lastContext = null;

	///////////////////////////////////////////////////////////
	// check array initializer
	filename = "shell.d";
	source = q{
		module shell;
		alias uint VSITEMID;
		const VSITEMID VSITEMID_NIL = cast(VSITEMID)(-1);
	};
	m = checkErrors(source, "");
	source = q{
		import shell;
		void ffoo()
		{
			if (uint(1) == VSITEMID_NIL) {} // Line 5
		}
	};
	filename = "source.d";
	m = checkErrors(source, "");

	// TODO: checkTip(m, 3, 18, "(enum) `tok.TOK`");
	checkTip(m, 5, 19, "(constant global) `const(uint) shell.VSITEMID_NIL`");
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
	opts.warnings = true;
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
			initErrorMessages(filename);
			Module parsedModule = createModuleFromText(filename, src);
			assert(parsedModule);
			Module m = analyzeModule(parsedModule, opts);
			auto err = getErrorMessages();
			auto other = getErrorMessages(true);
			assert_equal(err, expected_err);
			assert_equal(other, "");
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

version(test):

// https://issues.dlang.org/show_bug.cgi?id=20253
enum TTT = 9;
void dummy()
{
	import std.file;
	std.file.read(""); // no tip on std and file
	auto x = TTT;
	int[] arr;
	auto s = arr.ptr;
	auto y = arr.length;
	enum my = arr.mangleof;
	enum zi = size_t.init;
	enum z0 = size_t.min;
	enum z1 = size_t.max;
	enum z2 = size_t.alignof;
	enum z3 = size_t.stringof;
	enum z4 = size_t.mangleof;
	cfloat flt = cfloat.nan;
	auto q = [flt.sizeof, flt.init, flt.epsilon, flt.mant_dig, flt.infinity,
			  flt.re, flt.im, flt.min_normal, flt.min_10_exp];
	//auto ti = Object.classinfo;
}

struct XMem
{
	int x;
	void foo2(int xx = TTT + 1);
	static XMem foo(int sz) { return XMem(); }
}
__gshared XMem xmem;
auto foo3(ref XMem x, @uda(EE) int sz)
{
	XMem m;
	m.x = 3;
	fun!XMem(x);
	return x;
}

template Templ(T, int n)
{
	struct Templ
	{
		T payload;
	}
}

import vdc.dmdserver.dmdinit;

void fun(T)(T p) if(TTT == 9)
{
	Templ!(XMem, TTT) arr;
	vdc.dmdserver.semanalysis.XMem m1 = vdc.dmdserver.semanalysis.xmem.foo(1234);
	vdc.dmdserver.semanalysis.XMem m2 = vdc.dmdserver.semanalysis.xmem.foo(1234);
	Enum* ee;
}
void goo()
{
	import std.file; 
	XMem m;
	vdc.dmdserver.semanalysis.foo3(m, 1234);
	std.file.read("abc");
}
enum Enum
{
	En1, En2, En3
}

alias En1 = Enum.En1;
enum EE = Enum.En2;
alias object.Object E1;
alias E2 = EE;
alias E3 = E2;
alias ET(T) = T.sizeof;   // Line 5
enum msg = "huhu";

@nogc:
struct uda { int x; string y; }
@EE @uda(EE, msg) shared int x;

import core.memory;
static assert(__traits(compiles, () { Enum ee = En1; }));
static assert(!__traits(compiles, () { Enum ee = En; }));

int abc;

void funky()
{
	int a = 1;
	if (a == 1)
	{
	}
}
