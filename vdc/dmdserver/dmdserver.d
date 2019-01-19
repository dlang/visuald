// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver;

version(MAIN) {} else version = noServer;

version(noServer):
import vdc.ivdserver;
import vdc.semanticopt;

import dmd.apply;
import dmd.arraytypes;
import dmd.builtin;
import dmd.cond;
import dmd.console;
import dmd.dclass;
import dmd.declaration;
import dmd.dimport;
import dmd.dinterpret;
import dmd.dmodule;
import dmd.dscope;
import dmd.dstruct;
import dmd.dsymbol;
import dmd.dsymbolsem;
import dmd.dtemplate;
import dmd.expression;
import dmd.func;
import dmd.globals;
import dmd.hdrgen;
import dmd.id;
import dmd.identifier;
import dmd.init;
import dmd.mtype;
import dmd.objc;
import dmd.sapply;
import dmd.semantic2;
import dmd.semantic3;
import dmd.statement;
import dmd.target;
import dmd.tokens;
import dmd.visitor;

import dmd.root.outbuffer;
import dmd.root.rmem;
import dmd.root.rootobject;

//import vdc.util;
struct TextPos
{
	int index;
	int line;
}
struct TextSpan
{
	TextPos start;
	TextPos end;
}

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

import stdext.com;
import stdext.string;
import stdext.array;

version = SingleThread;

//import std.stdio;
import std.parallelism;
import std.path;
import std.string;
import std.conv;
import std.array;

import std.concurrency;
import std.datetime;
import core.exception;
import core.memory;
import core.thread;
import core.time;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

//version = traceGC;
version (traceGC) import tracegc;

debug version = DebugServer;
//debug version = vdlog; // log through visual D logging (needs version = InProc in vdserverclient)

shared(Object) gDMDSync = new Object; // no multi-instances/multi-threading with DMD
shared(Object) gOptSync = new Object; // no multi-instances/multi-threading with DMD

extern(C) __gshared string[] rt_options = [ "scanDataSeg=precise" ];

///////////////////////////////////////////////////////////////////////
version(DebugServer)
{
	import std.windows.charset;
	import std.datetime;
	version(vdlog) debug import visuald.logutil;
	import core.stdc.stdio : fprintf, fopen, fputc, fflush, FILE;
	__gshared FILE* dbgfh;

	void dbglog(const(char)[] s)
	{
		debug
		{
			version(vdlog)
				logCall("DMDServer: ", s);
			else
				sdk.win32.winbase.OutputDebugStringA(toMBSz("DMDServer: " ~ s ~ "\n"));
		}
		else
		{
			if(!dbgfh)
				dbgfh = fopen("c:/tmp/dmdserver.log", "w");

			SysTime now = Clock.currTime();
			uint tid = sdk.win32.winbase.GetCurrentThreadId();
			auto len = fprintf(dbgfh, "%02d:%02d:%02d - %04x - ",
							   now.hour, now.minute, now.second, tid);
			fprintf(dbgfh, "%.*s", s.length, s.ptr);
			fputc('\n', dbgfh);
			fflush(dbgfh);
		}
	}
}

alias object.AssociativeArray!(string, std.concurrency.Tid) _wa1; // fully instantiate type info for string[Tid]
alias object.AssociativeArray!(std.concurrency.Tid, string[]) _wa2; // fully instantiate type info for string[Tid]

///////////////////////////////////////////////////////////////

struct delegate_fake
{
	ptrdiff_t ptr;
	ptrdiff_t context;
}

class DMDServer : ComObject, IVDServer
{
	this()
	{
		version(unittest) {} else
			version(SingleThread) mTid = spawn(&taskLoop, thisTid);
		mOptions = new Options;

		synchronized(gDMDSync)
		{
			global._init();
			global.params.isWindows = true;
			global.params.errorLimit = 0;
		}
	}

	override ULONG Release()
	{
		if(count == 1 && mTid != mTid.init)
		{
			// avoid recursive calls if the object is temporarily ref-counted
			// while executing Dispose()
			count = 0x12345678;

			send(mTid, "stop");
			receive((string val) { assert(val == "done"); });

			assert(count == 0x12345678);
			count = 1;
		}
		return super.Release();
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
//		MessageBoxW(null, "Object1.QueryInterface"w.ptr, "[LOCAL] message", MB_OK|MB_SETFOREGROUND);
		if(queryInterface!(IVDServer) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	extern(D) static void taskLoop(Tid tid)
	{
		bool cont = true;
		while(cont)
		{
			try
			{
				receiveTimeout(dur!"msecs"(50),
							   (delegate_fake dg_fake)
							   {
								void delegate() dg = *(cast(void delegate()*)&dg_fake);
								dg();
							   },
							   (string cmd)
							   {
								if(cmd == "stop")
									cont = false;
							   },
							   (Variant var)
							   {
								var = var;
							   }
							   );
			}
			catch(OutOfMemoryError e)
			{
				exit(7); // terminate
			}
			catch(Throwable e)
			{
				version(DebugCmd) dbglog ("taskLoop exception: " ~ e.msg);
			}
		}
		prioritySend(tid, "done");
	}

	extern(D) void schedule(void delegate() dg)
	{
		version(unittest)
			dg();
		else version(SingleThread)
			send(mTid, *cast(delegate_fake*)&dg);
		else
			runTask(dg);
	}

	override HRESULT ConfigureSemanticProject(in BSTR filename, in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, DWORD flags)
	{
		string fname = to_string(filename);


		synchronized(gOptSync)
		{
			auto opts = mOptions;

			string imports = to_string(imp);
			string strImports = to_string(stringImp);

			uint oldflags = ConfigureFlags!()(opts.unittestOn, opts.debugOn, opts.x64,
											  opts.coverage, opts.doDoc, opts.noBoundsCheck, opts.gdcCompiler,
											  0, 0, // no need to compare version levels, done in setVersionIds
											  opts.noDeprecated, opts.ldcCompiler, opts.msvcrt,
											  opts.mixinAnalysis, opts.UFCSExpansions);

			opts.unittestOn     = (flags & 1) != 0;
			opts.debugOn        = (flags & 2) != 0;
			opts.x64            = (flags & 4) != 0;
			opts.coverage       = (flags & 8) != 0;
			opts.doDoc          = (flags & 16) != 0;
			opts.noBoundsCheck  = (flags & 32) != 0;
			opts.gdcCompiler    = (flags & 64) != 0;
			opts.noDeprecated   = (flags & 128) != 0;
			opts.mixinAnalysis  = (flags & 0x1_00_00_00) != 0;
			opts.UFCSExpansions = (flags & 0x2_00_00_00) != 0;
			opts.ldcCompiler    = (flags & 0x4_00_00_00) != 0;
			opts.msvcrt         = (flags & 0x8_00_00_00) != 0;

			int versionlevel = (flags >> 8)  & 0xff;
			int debuglevel   = (flags >> 16) & 0xff;

			string verids = to_string(versionids);
			string dbgids = to_string(debugids);

			int changed = (oldflags != (flags & 0xff0000ff));
			changed += opts.setImportDirs(splitLines(imports));
			changed += opts.setStringImportDirs(splitLines(strImports));
			changed += opts.setVersionIds(versionlevel, splitLines(verids));
			changed += opts.setDebugIds(debuglevel, splitLines(dbgids));
		}
		return S_OK;
	}

	override HRESULT ClearSemanticProject()
	{
		/+
		synchronized(mSemanticProject)
			mSemanticProject.disconnectAll();

		mSemanticProject = new vdc.semantic.Project;
		mSemanticProject.saveErrors = true;
		+/
		return S_OK;
	}

	override HRESULT UpdateModule(in BSTR filename, in BSTR srcText, in DWORD flags)
	{
		string fname = to_string(filename);
		size_t len = wcslen(srcText);
		string text  = to_string(srcText, len + 1); // DMD parser needs trailing 0
		text = text[0..$-1];

		Module mod;
		bool doCancel = false;
		synchronized(gErrorSync)
		{
			// cancel existing
			mod = findModule(fname, false);
			if (mod)
			{
				if (auto pErr = cast(void*)mod in mErrors)
					if (*pErr == "__parsing__")
						doCancel = true;
			}

			// always create new module
			mod = findModule(fname, true);
			mod.srcfile.setbuffer(cast(char*)(text.ptr), text.length);
			mod.srcfile._ref = 1; // do not own buffer

			mErrors[cast(void*)mod] = "__pending__";
		}
		if (doCancel)
		{
			Mem.cancel = true;
			synchronized(gDMDSync)
			{
				// wait for parsing done
				Mem.cancel = false;
			}
		}

		void doParse()
		{
			version(DebugServer) dbglog("    doParse: " ~ firstLine(text));

			synchronized(gErrorSync)
			{
				auto pErr = cast(void*)mod in mErrors;
				if (!pErr)
					return; // already relaced by a new request

				*pErr = "__parsing__";
			}
			string errors;
			synchronized(gDMDSync)
			{
				try
				{
					initErrorFile(fname);
					parseModules([mod]);
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) dbglog("UpdateModule.doParse: exception " ~ t.msg);
				}
				errors = cast(string) gErrorMessages;
			}
			synchronized(gErrorSync)
			{
				if (auto pErr = cast(void*)mod in mErrors)
					*pErr = errors;
			}

			if(flags & 1)
				writeReadyMessage();
		}
		version(DebugServer) dbglog("  scheduleParse: " ~ firstLine(text));
		schedule(&doParse);
		return S_OK;
	}

	override HRESULT GetParseErrors(in BSTR filename, BSTR* errors)
	{
		string fname = to_string(filename);

		if(auto mod = findModule(fname, false))
		{
			synchronized(gErrorSync)
			{
				if (auto pError = cast(void*)mod in mErrors)
				{
					if (*pError != "__pending__" && *pError != "__parsing__")
					{
						version(DebugServer)
							dbglog("GetParseErrors: " ~ *pError);

						*errors = allocBSTR(*pError);
						return S_OK;
					}
				}
			}
		}
		return S_FALSE;
	}

	override HRESULT GetTip(in BSTR filename, int startLine, int startIndex, int endLine, int endIndex, int flags)
	{
		string fname = to_string(filename);

		mTipSpan.start.line  = startLine;
		mTipSpan.start.index = startIndex;
		mTipSpan.end.line    = endLine;
		mTipSpan.end.index   = endIndex;

		Module m;
		synchronized(gErrorSync)
		{
			m = findModule(fname, false);
			if (!m)
				return S_FALSE;
		}

		void _getTip()
		{
			string txt;
			synchronized(gDMDSync)
			{
				try
				{
					txt = findTip(m, startLine, startIndex + 1, endLine, endIndex + 1);
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) dbglog("GetTip: exception " ~ t.msg);
					txt = "exception: " ~ t.msg;
				}
			}
			mLastTip = txt;
			mSemanticTipRunning = false;
		}
		version(DebugServer) dbglog("  schedule GetTip: " ~ fname);
		mSemanticTipRunning = true;
		schedule(&_getTip);

		return S_OK;
	}

	override HRESULT GetTipResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer)
	{
		if(mSemanticTipRunning)
		{
			*answer = allocBSTR("__pending__");
			return S_OK;
		}

		version(DebugServer) dbglog("GetTipResult: " ~ mLastTip);
		writeReadyMessage();
		startLine  = mTipSpan.start.line;
		startIndex = mTipSpan.start.index;
		endLine    = mTipSpan.end.line;
		endIndex   = mTipSpan.end.index;
		*answer = allocBSTR(mLastTip);
		return S_OK;
	}

	override HRESULT GetDefinition(in BSTR filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		string fname = to_string(filename);

		mDefSpan.start.line  = startLine;
		mDefSpan.start.index = startIndex;
		mDefSpan.end.line    = endLine;
		mDefSpan.end.index   = endIndex;

		Module m;
		synchronized(gErrorSync)
		{
			m = findModule(fname, false);
			if (!m)
				return S_FALSE;
		}

		void _getDefinition()
		{
			string deffilename;
			synchronized(gDMDSync)
			{
				try
				{
					deffilename = findDefinition(m, mDefSpan.start.line, mDefSpan.start.index);
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) dbglog("GetDefinition: exception " ~ t.msg);
				}
			}
			mLastDefFile = deffilename;
			mSemanticDefinitionRunning = false;
		}
		version(DebugServer) dbglog("  schedule GetDefinition: " ~ fname);
		mSemanticDefinitionRunning = true;
		schedule(&_getDefinition);

		return S_OK;
	}

	override HRESULT GetDefinitionResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer)
	{
		if(mSemanticDefinitionRunning)
		{
			*answer = allocBSTR("__pending__");
			return S_OK;
		}

		version(DebugServer) dbglog("GetDefinitionResult: " ~ mLastDefFile);
		writeReadyMessage();
		startLine  = mDefSpan.start.line;
		startIndex = mDefSpan.start.index;
		endLine    = mDefSpan.start.line;
		endIndex   = mDefSpan.start.index + 1;
		*answer = allocBSTR(mLastDefFile);
		return S_OK;
	}

	override HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx, in BSTR expr)
	{
		string[] symbols;
		string fname = to_string(filename);
		/+
		auto src = mSemanticProject.getModuleByFilename(fname);
		if(!src)
			return S_FALSE;

		string stok = to_string(tok);
		string sexpr = to_string(expr);
		void calcExpansions()
		{
			fnSemanticWriteError = &semanticWriteError;
			try
			{
				mLastSymbols = null; //_GetSemanticExpansions(src, stok, line, idx, sexpr);
			}
			catch(OutOfMemoryError e)
			{
				throw e; // terminate
			}
			catch(Throwable t)
			{
				version(DebugServer) dbglog("GetSemanticExpansions.calcExpansions: exception " ~ t.msg);
				logInfo(t.msg);
			}
			mSemanticExpansionsRunning = false;
		}
		version(DebugServer) dbglog("  schedule GetSemanticExpansions: " ~ fname);
		mLastSymbols = null;
		mSemanticExpansionsRunning = true;
		schedule(&calcExpansions);
		+/
		return S_OK;
	}

	override HRESULT GetSemanticExpansionsResult(BSTR* stringList)
	{
		if(mSemanticExpansionsRunning)
			return S_FALSE;

		Appender!string slist;
		foreach(sym; mLastSymbols)
		{
			slist.put(sym);
			slist.put('\n');
		}
		*stringList = allocBSTR(slist.data);

		version(DebugServer) dbglog("GetSemanticExpansionsResult: " ~ slist.data);
		writeReadyMessage();
		return S_OK;
	}

	// obsolete, implement GetBinaryIsInLocations
	override HRESULT IsBinaryOperator(in BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BOOL* pIsOp)
	{
		if(!pIsOp)
			return E_POINTER;

		*pIsOp = false;
		return S_OK;
	}

	override HRESULT ConfigureCommentTasks(in BSTR tasks)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetCommentTasks(in BSTR filename, BSTR* tasks)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetBinaryIsInLocations(in BSTR filename, VARIANT* locs)
	{
		// array of pairs of DWORD
		int[] locData;
		string fname = to_string(filename);
		/+
		synchronized(mSemanticProject)
			if(auto src = mSemanticProject.getModuleByFilename(fname))
				if(auto mod = src.parsed)
				{
					mod.visit(delegate bool (ast.Node n) {
						if(n.id == TOK_in || n.id == TOK_is)
							if(cast(ast.BinaryExpression) n)
							{
								locData ~= n.span.start.line;
								locData ~= n.span.start.index;
							}
						return true;
					});
				}
		+/
		SAFEARRAY *sa = SafeArrayCreateVector(VT_INT, 0, cast(ULONG) locData.length);
		if(!sa)
			return E_OUTOFMEMORY;

		for(LONG index = 0; index < locData.length; index++)
			SafeArrayPutElement(sa, &index, &locData[index]);

		locs.vt = VT_ARRAY;
		locs.parray = sa;
		return S_OK;
	}

	override HRESULT GetLastMessage(BSTR* message)
	{
		if(!mLastMessage.length)
		{
			if(mNextReadyMessage > Clock.currTime())
				return S_FALSE;

			mLastMessage = "Ready";
			mNextReadyMessage = Clock.currTime().add!"years"(1);
		}
		*message = allocBSTR(mLastMessage);
		mLastMessage = null;
		return S_OK;
	}

	override HRESULT GetReferences(in BSTR filename, in BSTR tok, uint line, uint idx, in BSTR expr)
	{
		return E_NOTIMPL;
	}

	override HRESULT GetReferencesResult(BSTR* stringList)
	{
		return E_NOTIMPL;
	}

	HRESULT GetIdentifierTypes(in BSTR filename, int startLine, int endLine, int flags)
	{
		return E_NOTIMPL;
	}

	HRESULT GetIdentifierTypesResult(BSTR* types)
	{
		return E_NOTIMPL;
	}

	///////////////////////////////////////////////////////////////
	// create our own task pool to be able to destroy it (it keeps a the
	//  arguments to the last task, so they are never collected)
	__gshared TaskPool parseTaskPool;

	void runTask(T)(T dg)
	{
		if(!parseTaskPool)
		{
			int threads = defaultPoolThreads;
			if(threads < 1)
				threads = 1;
			parseTaskPool = new TaskPool(threads);
			parseTaskPool.isDaemon = true;
			parseTaskPool.priority(core.thread.Thread.PRIORITY_MIN);
		}
		auto task = task(dg);
		parseTaskPool.put(task);
	}

	void writeReadyMessage()
	{
		if(mHadMessage)
		{
			mNextReadyMessage = Clock.currTime() + dur!"seconds"(2);
			mHadMessage = false;
		}
	}

	void parseModules(Module[] modules)
	{
		clearDmdStatics();

		// Initialization
		Token._init();
		Type._init();
		Id.initialize();
		Module._init();
		Target._init();
		Expression._init();
		Objc._init();
		builtin_init();
		Module.rootModule = null;
		global.gag = false;
		global.gaggedErrors = 0;
		global.errors = 0;
		global.warnings = 0;

		version(traceGC)
		{
			wipeStack();
			GC.collect();
			dumpGC();
		}
		else
			GC.collect();

		synchronized(gOptSync)
		{
			global.params.color = false;
			global.params.link = true;
			global.params.useAssert = mOptions.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
			global.params.useInvariants = mOptions.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
			global.params.useIn = mOptions.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
			global.params.useOut = mOptions.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
			global.params.useArrayBounds = mOptions.noBoundsCheck ? CHECKENABLE.on : CHECKENABLE.off; // set correct value later
			global.params.doDocComments = mOptions.doDoc;
			global.params.useSwitchError = CHECKENABLE.on;
			global.params.useInline = false;
			global.params.obj = false;
			global.params.useDeprecated = mOptions.noDeprecated ? Diagnostic.error : Diagnostic.off;
			global.params.linkswitches = Strings();
			global.params.libfiles = Strings();
			global.params.dllfiles = Strings();
			global.params.objfiles = Strings();
			global.params.ddocfiles = Strings();
			// Default to -m32 for 32 bit dmd, -m64 for 64 bit dmd
			global.params.is64bit = mOptions.x64;
			global.params.mscoff = mOptions.msvcrt;
			global.params.cpu = CPU.baseline;
			global.params.isLP64 = global.params.is64bit;

			global.params.versionlevel = mOptions.versionIds.level;
			global.params.versionids = new Strings();
			foreach(id, v; mOptions.versionIds.identifiers)
				global.params.versionids.push(toStringz(id));

			global.versionids = new Identifiers();

			// Add in command line versions
			if (global.params.versionids)
				foreach (charz; *global.params.versionids)
					VersionCondition.addGlobalIdent(charz[0 .. strlen(charz)]);

/*
			VersionCondition.addPredefinedGlobalIdent("DigitalMars");
			VersionCondition.addPredefinedGlobalIdent("Windows");
			VersionCondition.addPredefinedGlobalIdent("LittleEndian");
			VersionCondition.addPredefinedGlobalIdent("D_Version2");
			VersionCondition.addPredefinedGlobalIdent("all");
			if (global.params.is64bit)
			{
				VersionCondition.addPredefinedGlobalIdent("D_InlineAsm_X86_64");
				VersionCondition.addPredefinedGlobalIdent("X86_64");
				VersionCondition.addPredefinedGlobalIdent("Win64");
			}
			else
			{
				VersionCondition.addPredefinedGlobalIdent("D_InlineAsm"); //legacy
				VersionCondition.addPredefinedGlobalIdent("D_InlineAsm_X86");
				VersionCondition.addPredefinedGlobalIdent("X86");
				VersionCondition.addPredefinedGlobalIdent("Win32");
			}
			if (global.params.mscoff || global.params.is64bit)
				VersionCondition.addPredefinedGlobalIdent("CRuntime_Microsoft");
			else
				VersionCondition.addPredefinedGlobalIdent("CRuntime_DigitalMars");
			if (global.params.isLP64)
				VersionCondition.addPredefinedGlobalIdent("D_LP64");
			if (global.params.doDocComments)
				VersionCondition.addPredefinedGlobalIdent("D_Ddoc");
			if (global.params.cov)
				VersionCondition.addPredefinedGlobalIdent("D_Coverage");
			if (global.params.pic)
				VersionCondition.addPredefinedGlobalIdent("D_PIC");
			if (global.params.useUnitTests)
				VersionCondition.addPredefinedGlobalIdent("unittest");
			if (global.params.useAssert)
				VersionCondition.addPredefinedGlobalIdent("assert");
			if (global.params.useArrayBounds == CHECKENABLE.off)
				VersionCondition.addPredefinedGlobalIdent("D_NoBoundsChecks");
			if (global.params.betterC)
				VersionCondition.addPredefinedGlobalIdent("D_betterC");
*/
			// always enable for tooltips
			global.params.doDocComments = true;

			global.params.debugids = new Strings();
			global.params.debuglevel = mOptions.debugIds.level;
			foreach(id, v; mOptions.debugIds.identifiers)
				global.params.debugids.push(toStringz(id));

			global.debugids = new Identifiers();
			if (global.params.debugids)
				foreach (charz; *global.params.debugids)
					DebugCondition.addGlobalIdent(charz[0 .. strlen(charz)]);

			global.path = new Strings();
			foreach(i; mOptions.importDirs)
				global.path.push(toStringz(i));

			global.filePath = new Strings();
			foreach(i; mOptions.stringImportDirs)
				global.filePath.push(toStringz(i));
		}

		// redo module name with the new Identifier.stringtable
		foreach (m; modules)
		{
			auto fname = m.srcfile.name.toString();
			auto name = stripExtension(baseName(fname));
			m.ident = Identifier.idPool(name);
		}

		for (size_t i = 0; i < modules.length; i++)
		{
			Module m = modules[i];
			m.read(Loc());
		}
		size_t filecount = modules.length;
		for (size_t filei = 0, modi = 0; filei < filecount; filei++, modi++)
		{
			Module m = modules[modi];
			if (!Module.rootModule)
				Module.rootModule = m;
			m.importedFrom = m;
			m.parse();
		}
		for (size_t i = 0; i < modules.length; i++)
		{
			Module m = modules[i];
			m.importAll(null);
		}

		// Do semantic analysis
		for (size_t i = 0; i < modules.length; i++)
		{
			Module m = modules[i];
			m.dsymbolSemantic(null);
		}

		Module.dprogress = 1;
		Module.runDeferredSemantic();

		// Do pass 2 semantic analysis
		for (size_t i = 0; i < modules.length; i++)
		{
			Module m = modules[i];
			m.semantic2(null);
		}
		Module.runDeferredSemantic2();

		// Do pass 3 semantic analysis
		for (size_t i = 0; i < modules.length; i++)
		{
			Module m = modules[i];
			m.semantic3(null);
		}
		Module.runDeferredSemantic3();
	}

private:
	static void clearModule(Module m)
	{
		m.insearch = 0;
		m.searchCacheIdent = null;
		m.searchCacheSymbol = null;  // cached value of search
		m.searchCacheFlags = 0;      // cached flags

		m.importedFrom = null;
		m.decldefs = null;           // top level declarations for this Module
		m.aimports = Modules();      // all imported modules

		m.debuglevel = 0;            // debug level
		m.debugids = null;           // debug identifiers
		m.debugidsNot = null;        // forward referenced debug identifiers

		m.versionlevel = 0;          // version level
		m.versionids = null;         // version identifiers
		m.versionidsNot = null;      // forward referenced version identifiers

		m.macrotable = null;         // document comment macros
		m.escapetable = null;        // document comment escapes

		m._scope = null;             // !=null means context to use for semantic()
		m.prettystring = null;       // cached value of toPrettyChars()
		m.errors = 0;                // this symbol failed to pass semantic()
	}

	Module findModule(string fname, bool createNew)
	{
		size_t pos = mModules.length;
		foreach (i, m; mModules)
			if (_stricmp(m.srcfile.name.toChars(), fname) == 0)
			{
				if (createNew)
				{
					pos = i;
					break;
				}
				return m;
			}

		if (!createNew)
			return null;

		auto m = new Module(toStringz(fname), null, false, false);
		if (pos < mModules.length)
		{
			mErrors.remove(cast(void*)mModules[pos]);
			mModules[pos] = m;
		}
		else
			mModules ~= m;
		return m;
	}

	version(SingleThread) Tid mTid;

	Options mOptions;
	Module[] mModules;
	string[void*] mErrors; // cannot index by C++ class Module

	bool mSemanticExpansionsRunning;
	bool mSemanticTipRunning;
	bool mSemanticDefinitionRunning;

	string mModuleToParse;
	string mLastTip;
	TextSpan mTipSpan;
	string mLastDefFile;
	TextSpan mDefSpan;
	string[] mLastSymbols;
	string mLastMessage;
	string mLastError;
	bool mHadMessage;
	SysTime mNextReadyMessage;
}

shared(Object) gErrorSync = new Object;
__gshared string gErrorFile;
__gshared char[] gErrorMessages;
__gshared char[] gOtherErrorMessages;
__gshared bool gErrorWasSupplemental;

extern(C++)
void verrorPrint(const ref Loc loc, Color headerColor, const(char)* header,
				 const(char)* format, va_list ap, const(char)* p1 = null, const(char)* p2 = null)
{
	if (!loc.filename)
		return;

	import dmd.errors;

	synchronized(gErrorSync)
	{
		bool other = _stricmp(loc.filename, gErrorFile) != 0;
		bool supplemental = (cast(Classification)headerColor == Classification.supplemental);

		__gshared char[4096] buf;
		int len = 0;
		if (other)
		{
			len = snprintf(buf.ptr, buf.length, "%s(%d):", loc.filename, loc.linnum);
		}
		else
		{
			int llen = snprintf(buf.ptr, buf.length, "%d,%d,%d,%d:", loc.linnum, loc.charnum - 1, loc.linnum, loc.charnum);
			gErrorMessages ~= buf[0..llen];
			if (supplemental)
				gErrorMessages ~= gOtherErrorMessages;
			gOtherErrorMessages = null;
		}
		if (p1 && len < buf.length)
			len += snprintf(buf.ptr + len, buf.length - len, "%s ", p1);
		if (p2 && len < buf.length)
			len += snprintf(buf.ptr + len, buf.length - len, "%s ", p2);
		if (len < buf.length)
			len += vsnprintf(buf.ptr + len, buf.length - len, format, ap);
		char nl = other ? '\a' : '\n';
		if (len < buf.length)
			buf[len++] = nl;
		else
			buf[$-1] = nl;

		dbglog(buf[0..len]);

		if (other)
		{
			if (gErrorWasSupplemental)
			{
				if (gErrorMessages.length && gErrorMessages[$-1] == '\n')
					gErrorMessages[$-1] = '\a';
				gErrorMessages ~= buf[0..len];
				gErrorMessages ~= '\n';
			}
			else if (supplemental)
				gOtherErrorMessages ~= buf[0..len];
			else
			{
				gErrorWasSupplemental = false;
				gOtherErrorMessages = buf[0..len].dup;
			}
		}
		else
		{
			gErrorMessages ~= buf[0..len];
			gErrorWasSupplemental = supplemental;
		}
	}
}

void initErrorFile(string fname)
{
	synchronized(gErrorSync)
	{
		gErrorFile = fname;
		gErrorMessages = null;
		gOtherErrorMessages = null;
		gErrorWasSupplemental = false;
	}
}

int _stricmp(const(char)*str1, string s2)
{
	const(char)[] s1 = str1[0..strlen(str1)];
	return icmp(s1, s2);
}

int _stricmp(const(wchar)*str1, wstring s2)
{
	const(wchar)[] s1 = str1[0..wcslen(str1)];
	return icmp(s1, s2);
}

////////////////////////////////////////////////////////////////
version(all) // new mangling with dmd version >= 2.077
{
	enum string[2][] dmdStatics =
	[
	["_D3dmd5clone12buildXtoHashFCQBa7dstruct17StructDeclarationPSQCg6dscope5ScopeZ8tftohashCQDh5mtype12TypeFunction", "TypeFunction"],
	["_D3dmd7dstruct15search_toStringRCQBfQBe17StructDeclarationZ10tftostringCQCs5mtype12TypeFunction", "TypeFunction"],
	["_D3dmd13expressionsem11loadStdMathFZ10impStdMathCQBv7dimport6Import", "Import"],
	["_D3dmd4func15FuncDeclaration8genCfuncRPSQBm4root5array__T5ArrayTCQCl5mtype9ParameterZQBcCQDjQy4TypeCQDu10identifier10IdentifiermZ2stCQFb7dsymbol12DsymbolTable", "DsymbolTable"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ3feqCQEn4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ4fcmpCQEo4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ5fhashCQEp4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd6dmacro5Macro6expandMFPSQBc4root9outbuffer9OutBufferkPkAxaZ4nesti", "int"], // x86
	["_D3dmd7dmodule6Module19runDeferredSemanticRZ6nestedi", "int"],
	["_D3dmd10dsymbolsem22DsymbolSemanticVisitor5visitMRCQBx9dtemplate13TemplateMixinZ4nesti", "int"],
	["_D3dmd9dtemplate16TemplateInstance16tryExpandMembersMFPSQCc6dscope5ScopeZ4nesti", "int"],
	["_D3dmd9dtemplate16TemplateInstance12trySemantic3MFPSQBy6dscope5ScopeZ4nesti", "int"],
	["_D3dmd13expressionsem25ExpressionSemanticVisitor5visitMRCQCd10expression7CallExpZ4nesti", "int"],
	//["_D3dmd7typesem6dotExpFCQv5mtype4TypePSQBk6dscope5ScopeCQCb10expression10ExpressionCQDd10identifier10IdentifieriZ11visitAArrayMFCQEwQEc10TypeAArrayZ8fd_aaLenCQFz4func15FuncDeclaration", "FuncDeclaration"],
	//["_D3dmd7typesem6dotExpFCQv5mtype4TypePSQBk6dscope5ScopeCQCb10expression10ExpressionCQDd10identifier10IdentifieriZ8noMemberMFQDxQDmQCxQByiZ4nesti", "int"],
	];
}
else
{
	enum string[2][] dmdStatics =
	[
		["D4ddmd5clone12buildXtoHashRC4ddmd7dstruct17StructDeclarationPS4ddmd6dscope5ScopeZ8tftohashC4ddmd5mtype12TypeFunction", "TypeFunction"],
		["D4ddmd7dstruct15search_toStringRC4ddmd7dstruct17StructDeclarationZ10tftostringC4ddmd5mtype12TypeFunction", "TypeFunction"],
		["D4ddmd10expression11loadStdMathRZ10impStdMathC4ddmd7dimport6Import", "Import"],
		["D4ddmd4func15FuncDeclaration8genCfuncRPS4ddmd4root5array33__T5ArrayTC4ddmd5mtype9ParameterZ5ArrayC4ddmd5mtype4TypeC4ddmd10identifier10IdentifiermZ2stC4ddmd7dsymbol12DsymbolTable", "DsymbolTable"],
		["D4ddmd5mtype10TypeAArray6dotExpMRPS4ddmd6dscope5ScopeC4ddmd10expression10ExpressionC4ddmd10identifier10IdentifieriZ8fd_aaLenC4ddmd4func15FuncDeclaration", "FuncDeclaration"],
		["D4ddmd7typesem19TypeSemanticVisitor5visitMRC4ddmd5mtype10TypeAArrayZ3feqC4ddmd4func15FuncDeclaration", "FuncDeclaration"],
		["D4ddmd7typesem19TypeSemanticVisitor5visitMRC4ddmd5mtype10TypeAArrayZ4fcmpC4ddmd4func15FuncDeclaration", "FuncDeclaration"],
		["D4ddmd7typesem19TypeSemanticVisitor5visitMRC4ddmd5mtype10TypeAArrayZ5fhashC4ddmd4func15FuncDeclaration", "FuncDeclaration"],

		["D4ddmd7dmodule6Module19runDeferredSemanticRZ6nestedi", "int"],
		["D4ddmd10dsymbolsem22DsymbolSemanticVisitor5visitMRC4ddmd9dtemplate13TemplateMixinZ4nesti", "int"],
		["D4ddmd9dtemplate16TemplateInstance16tryExpandMembersMRPS4ddmd6dscope5ScopeZ4nesti", "int"],
		["D4ddmd9dtemplate16TemplateInstance12trySemantic3MRPS4ddmd6dscope5ScopeZ4nesti", "int"],
		["D4ddmd13expressionsem25ExpressionSemanticVisitor5visitMRC4ddmd10expression7CallExpZ4nesti", "int"],
		["D4ddmd5mtype4Type8noMemberMRPS4ddmd6dscope5ScopeC4ddmd10expression10ExpressionC4ddmd10identifier10IdentifieriZ4nesti", "int"],
	];
}

string cmangled(string s)
{
	version (Win64)
		if (s ==   "_D3dmd6dmacro5Macro6expandMFPSQBc4root9outbuffer9OutBufferkPkAxaZ4nesti")
			return "_D3dmd6dmacro5Macro6expandMFPSQBc4root9outbuffer9OutBuffermPmAxaZ4nesti";
	return s;
}
string genDeclDmdStatics()
{
	string s;
	foreach (decl; dmdStatics)
		s ~= q{extern extern(C) __gshared } ~ decl[1] ~ " " ~ cmangled(decl[0]) ~ ";\n";
	return s;
}

string genInitDmdStatics()
{
	string s;
	foreach (decl; dmdStatics)
		s ~= cmangled(decl[0]) ~ " = " ~ decl[1] ~ ".init;\n";
	return s;
}

mixin(genDeclDmdStatics);

void clearDmdStatics()
{
	/*
	import core.demangle;
	static foreach(s; dmdStatics)
		pragma(msg, demangle(s[0]));
	*/
	mixin(genInitDmdStatics);

	Module.rootModule = null;
	Module.modules = null;     // symbol table of all modules
	Module.amodules = Modules();    // array of all modules
	Module.deferred = Dsymbols();    // deferred Dsymbol's needing semantic() run on them
	Module.deferred2 = Dsymbols();   // deferred Dsymbol's needing semantic2() run on them
	Module.deferred3 = Dsymbols();   // deferred Dsymbol's needing semantic3() run on them
	Module.dprogress = 0;      // progress resolving the deferred list
	Module.moduleinfo = null;

	ClassDeclaration.object = null;
	ClassDeclaration.throwable = null;
	ClassDeclaration.exception = null;
	ClassDeclaration.errorException = null;
	ClassDeclaration.cpp_type_info_ptr = null;

	StructDeclaration.xerreq = null;
	StructDeclaration.xerrcmp = null;

	Type.dtypeinfo = null;
	Type.typeinfoclass = null;
	Type.typeinfointerface = null;
	Type.typeinfostruct = null;
	Type.typeinfopointer = null;
	Type.typeinfoarray = null;
	Type.typeinfostaticarray = null;
	Type.typeinfoassociativearray = null;
	Type.typeinfovector = null;
	Type.typeinfoenum = null;
	Type.typeinfofunction = null;
	Type.typeinfodelegate = null;
	Type.typeinfotypelist = null;
	Type.typeinfoconst = null;
	Type.typeinfoinvariant = null;
	Type.typeinfoshared = null;
	Type.typeinfowild = null;
	Type.rtinfo = null;
	Type.stringtable.reset();

	// statementsem
	// static __gshared FuncDeclaration* fdapply = [null, null];
	// static __gshared TypeDelegate* fldeTy = [null, null];

	// dmd.dinterpret
	// ctfeStack = ctfeStack.init;

	// dmd.dtemplate
	emptyArrayElement = null;
	TemplateValueParameter.edummies = null;

	Scope.freelist = null;
	//Token.freelist = null;

	Identifier.initTable();
}

////////////////////////////////////////////////////////////////
Loc endLoc(Dsymbol sym)
{
	return Loc();
}

// walk the complete AST (declarations, statement and expressions)
// assumes being started on module/declaration level
extern(C++) class ASTVisitor : StoppableVisitor
{
	alias visit = super.visit;

	void visitExpression(Expression expr)
	{
		if (stop || !expr)
			return;

		if (walkPostorder(expr, this))
			stop = true;
	}

	void visitStatement(Statement stmt)
	{
		if (stop || !stmt)
			return;

		if (walkPostorder(stmt, this))
			stop = true;
	}

	void visitDeclaration(Dsymbol sym)
	{
		if (stop || !sym)
			return;

		sym.accept(this);
	}

	// override void visit(Expression) {}
	// override void visit(Parameter) {}
	// override void visit(Statement) {}
	// override void visit(Type) {}
	// override void visit(TemplateParameter) {}
	// override void visit(Condition) {}
	// override void visit(Initializer) {}

	override void visit(ScopeDsymbol scopesym)
	{
		// optimize to only visit members in approriate source range
		size_t mcnt = scopesym.members ? scopesym.members.dim : 0;
		for (size_t m = 0; !stop && m < mcnt; m++)
		{
			Dsymbol s = (*scopesym.members)[m];
			s.accept(this);
		}
	}

	override void visit(VarDeclaration decl)
	{
		visit(cast(Declaration)decl);

		if (!stop && decl._init)
			decl._init.accept(this);
	}

	override void visit(ExpInitializer einit)
	{
		visitExpression(einit.exp);
	}

	override void visit(VoidInitializer vinit)
	{
	}

	override void visit(StructInitializer sinit)
	{
		foreach (i, const id; sinit.field)
			if (auto iz = sinit.value[i])
				iz.accept(this);
	}

	override void visit(ArrayInitializer ainit)
	{
		foreach (i, ex; ainit.index)
		{
			if (ex)
				ex.accept(this);
			if (auto iz = ainit.value[i])
				iz.accept(this);
		}
	}

	override void visit(FuncDeclaration decl)
	{
		visit(cast(Declaration)decl);

		if (decl.parameters)
			foreach(p; *decl.parameters)
				if (!stop)
					p.accept(this);

		visitStatement(decl.frequire);
		visitStatement(decl.fensure);
		visitStatement(decl.fbody);
	}

	override void visit(ErrorStatement stmt)
	{
		visitStatement(stmt.errStmt);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ExpStatement stmt)
	{
		visitExpression(stmt.exp);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(CompileStatement stmt)
	{
		if (stmt.exps)
			foreach(e; *stmt.exps)
				if (!stop)
					e.accept(this);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(WhileStatement stmt)
	{
		visitExpression(stmt.condition);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(DoStatement stmt)
	{
		visitExpression(stmt.condition);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ForStatement stmt)
	{
		visitExpression(stmt.condition);
		visitExpression(stmt.increment);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ForeachStatement stmt)
	{
		if (stmt.parameters)
			foreach(p; *stmt.parameters)
				if (!stop)
					p.accept(this);
		visitExpression(stmt.aggr);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(ForeachRangeStatement stmt)
	{
		if (!stop && stmt.prm)
			stmt.prm.accept(this);
		visitExpression(stmt.lwr);
		visitExpression(stmt.upr);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(IfStatement stmt)
	{
		if (!stop && stmt.prm)
			stmt.prm.accept(this);
		visitExpression(stmt.condition);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(PragmaStatement stmt)
	{
		if (!stop && stmt.args)
			foreach(a; *stmt.args)
				if (!stop)
					a.accept(this);
		if (!stop)
			visit(cast(Statement)stmt);
	}

	override void visit(StaticAssertStatement stmt)
	{
		visitExpression(stmt.sa.exp);
		visitExpression(stmt.sa.msg);
		visit(cast(Statement)stmt);
	}

	override void visit(SwitchStatement stmt)
	{
		visitExpression(stmt.condition);
		visit(cast(Statement)stmt);
	}

	override void visit(CaseStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(CaseRangeStatement stmt)
	{
		visitExpression(stmt.first);
		visitExpression(stmt.last);
		visit(cast(Statement)stmt);
	}

	override void visit(GotoCaseStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(ReturnStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(SynchronizedStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(WithStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(TryCatchStatement stmt)
	{
		if (!stop && stmt.catches)
			foreach(c; *stmt.catches)
				visitDeclaration(c.var);
		visit(cast(Statement)stmt);
	}

	override void visit(ThrowStatement stmt)
	{
		visitExpression(stmt.exp);
		visit(cast(Statement)stmt);
	}

	override void visit(ImportStatement stmt)
	{
		if (!stop && stmt.imports)
			foreach(i; *stmt.imports)
				visitDeclaration(i);
		visit(cast(Statement)stmt);
	}

	override void visit(DeclarationExp expr)
	{
		visitDeclaration(expr.declaration);
	}

	override void visit(ErrorExp expr)
	{
		visitExpression(expr.errExp);
		if (!stop)
			visit(cast(Expression)expr);
	}

}

extern(C++) class FindASTVisitor : ASTVisitor
{
	const(char*) filename;
	int startLine;
	int startIndex;
	int endLine;
	int endIndex;

	alias visit = super.visit;
	RootObject found;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		this.filename = filename;
		this.startLine = startLine;
		this.startIndex = startIndex;
		this.endLine = endLine;
		this.endIndex = endIndex;
	}

	bool foundNode(RootObject obj)
	{
		if (!obj)
		{
			found = obj;
			stop = true;
		}
		return stop;
	}

	bool matchIdentifier(ref Loc loc, Identifier ident)
	{
		if (ident)
			if (loc.filename is filename)
				if (loc.linnum == startLine && loc.linnum == endLine)
					if (loc.charnum <= startIndex && loc.charnum + ident.toString().length >= endIndex)
						return true;
		return false;
	}

	bool matchLoc(ref Loc loc)
	{
		if (loc.filename is filename)
			if (loc.linnum == startLine && loc.linnum == endLine)
				if (loc.charnum <= startIndex /*&& loc.charnum + ident.toString().length >= endIndex*/)
					return true;
		return false;
	}

	override void visit(Dsymbol sym)
	{
		if (!found && matchIdentifier(sym.loc, sym.ident))
			foundNode(sym);
	}

	override void visit(Parameter sym)
	{
		//if (!found && matchIdentifier(sym.loc, sym.ident))
		//	foundNode(sym);
	}

	override void visit(ScopeDsymbol scopesym)
	{
		// optimize to only visit members in approriate source range
		size_t mcnt = scopesym.members ? scopesym.members.dim : 0;
		for (size_t m = 0; m < mcnt; m++)
		{
			Dsymbol s = (*scopesym.members)[m];
			if (s.isTemplateInstance)
				continue;
			if (s.loc.filename !is filename)
				continue;

			if (s.loc.linnum > endLine || (s.loc.linnum == endLine && s.loc.charnum > endIndex))
				continue;

			Loc nextloc;
			for (m++; m < mcnt; m++)
			{
				auto ns = (*scopesym.members)[m];
				if (ns.isTemplateInstance)
					continue;
				if (ns.loc.filename is filename)
				{
					nextloc = ns.loc;
					break;
				}
			}
			m--;

			if (nextloc.filename)
				if (nextloc.linnum < startLine || (nextloc.linnum == startLine && nextloc.charnum < startIndex))
					continue;

			s.accept(this);

			if (!found)
				foundNode(s);
			break;
		}
	}
	override void visit(TemplateInstance)
	{
		// skip members added by semantic
	}

	override void visit(Statement stmt)
	{
		// default to nothing
	}

	override void visit(CallExp expr)
	{
		super.visit(expr);
	}

	override void visit(Expression expr)
	{
		// default to nothing
	}
	override void visit(SymbolExp expr)
	{
		if (!found && expr.var)
			if (matchIdentifier(expr.loc, expr.var.ident))
				foundNode(expr);
	}
	override void visit(NewExp ne)
	{
		if (!found && matchLoc(ne.loc))
			if (ne.member)
				foundNode(ne.member);
			else
				foundNode(ne.type);
	}

	override void visit(DotIdExp de)
	{
		if (!found && de.ident)
			if (matchIdentifier(de.identloc, de.ident))
				foundNode(de);
	}

	override void visit(DotTemplateExp dte)
	{
		if (!found && dte.td && dte.td.ident)
			if (matchIdentifier(dte.identloc, dte.td.ident))
				foundNode(dte);
	}

	override void visit(TemplateExp te)
	{
		if (!found && te.td && te.td.ident)
			if (matchIdentifier(te.identloc, te.td.ident))
				foundNode(te);
	}

	override void visit(DotVarExp dve)
	{
		if (!found && dve.var && dve.var.ident)
			if (matchIdentifier(dve.varloc, dve.var.ident))
				foundNode(dve);
	}
}

extern(C++) class FindTipVisitor : FindASTVisitor
{
	string tip;

	alias visit = super.visit;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		super(filename, startLine, startIndex, endLine, endIndex);
	}

	void visitCallExpression(CallExp expr)
	{
		if (!found)
		{
			// replace function type with actual
			visitExpression(expr);
			if (found is expr.e1)
			{
				foundNode(expr);
			}
		}
	}

	override bool foundNode(RootObject obj)
	{
		found = obj;
		if (obj)
		{
			string tipForDeclaration(Declaration decl)
			{
				if (auto func = decl.isFuncDeclaration())
				{
					OutBuffer buf;
					if (decl.type)
						functionToBufferWithIdent(decl.type.toTypeFunction(), &buf, decl.toPrettyChars());
					else
						buf.writestring(decl.toPrettyChars());
					auto res = buf.peekSlice();
					buf.extractString(); // take ownership
					return cast(string)res;
				}

				string txt;
				if (decl.isParameter())
					txt = "(parameter) ";
				else if (!decl.isDataseg() && !decl.isCodeseg() && !decl.isField())
					txt = "(local variable) ";
				bool fqn = txt.empty;

				if (decl.type)
					txt ~= to!string(decl.type.toPrettyChars()) ~ " ";
				txt ~= to!string(fqn ? decl.toPrettyChars(fqn) : decl.toChars());
				return txt;
			}

			const(char)* toc = null;
			if (auto t = obj.isType())
				toc = t.toChars();
			else if (auto e = obj.isExpression())
			{
				switch(e.op)
				{
					case TOK.variable:
					case TOK.symbolOffset:
						tip = tipForDeclaration((cast(SymbolExp)e).var);
						break;
					case TOK.dotVariable:
						tip = tipForDeclaration((cast(DotVarExp)e).var);
						break;
					default:
						if (e.type)
							toc = e.type.toPrettyChars();
						break;
				}
			}
			else if (auto s = obj.isDsymbol())
			{
				if (auto decl = s.isDeclaration)
					tip = tipForDeclaration(decl);
				else
					toc = s.toPrettyChars(true);
			}
			if (!tip.length)
			{
				if (!toc)
					toc = obj.toChars();
				tip = to!string(toc);
			}
			// append doc
			stop = true;
		}
		return stop;
	}
}

RootObject _findAST(Dsymbol sym, const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
{
	scope FindASTVisitor fav = new FindASTVisitor(filename, startLine, startIndex, endLine, endIndex);
	sym.accept(fav);

	return fav.found;
}

RootObject findAST(Module mod, int startLine, int startIndex, int endLine, int endIndex)
{
	auto filename = mod.srcfile.name.toChars();
	return _findAST(mod, filename, startLine, startIndex, endLine, endIndex);
}

string findTip(Module mod, int startLine, int startIndex, int endLine, int endIndex)
{
	auto filename = mod.srcfile.name.toChars();
	scope FindTipVisitor ftv = new FindTipVisitor(filename, startLine, startIndex, endLine, endIndex);
	mod.accept(ftv);

	return ftv.tip;
}
////////////////////////////////////////////////////////////////

extern(C++) class FindDefinitionVisitor : FindASTVisitor
{
	Loc loc;

	alias visit = super.visit;

	this(const(char*) filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		super(filename, startLine, startIndex, endLine, endIndex);
	}

	override bool foundNode(RootObject obj)
	{
		found = obj;
		if (obj)
		{
			if (auto t = obj.isType())
			{
				if (t.ty == Tstruct)
					loc = (cast(TypeStruct)t).sym.loc;
			}
			else if (auto e = obj.isExpression())
			{
				switch(e.op)
				{
					case TOK.variable:
					case TOK.symbolOffset:
						loc = (cast(SymbolExp)e).var.loc;
						break;
					default:
						loc = e.loc;
						break;
				}
			}
			else if (auto s = obj.isDsymbol())
			{
				loc = s.loc;
			}
			stop = true;
		}
		return stop;
	}
}

string findDefinition(Module mod, ref int line, ref int index)
{
	auto filename = mod.srcfile.name.toChars();
	scope FindDefinitionVisitor fdv = new FindDefinitionVisitor(filename, line, index, line, index + 1);
	mod.accept(fdv);

	if (!fdv.loc.filename)
		return null;
	line = fdv.loc.linnum;
	index = fdv.loc.charnum;
	return to!string(fdv.loc.filename);
}

extern(C) int _CrtDumpMemoryLeaks();
extern(C) void dumpGC();

////////////////////////////////////////////////////////////////
unittest
{
	//_CrtDumpMemoryLeaks();
	version(traceGC)
		dumpGC();

	DMDServer srv = newCom!DMDServer;
	addref(srv);
	scope(exit) release(srv);

	auto filename = allocBSTR("source.d");
	auto imp = allocBSTR(r"c:\s\d\rainers\druntime\import" ~ "\n" ~
						 r"c:\s\d\rainers\phobos");
	auto empty = allocBSTR("");
	uint flags = ConfigureFlags!()(false, //bool unittestOn
								   false, //bool debugOn,
								   true,  //bool x64
								   false, //bool cov
								   false, //bool doc,
								   false, //bool nobounds,
								   false, //bool gdc,
								   0,     //int versionLevel,
								   0,     //int debugLevel,
								   false, //bool noDeprecated,
								   false, //bool ldc,
								   true,  //bool msvcrt,
								   true,  //bool mixinAnalysis,
								   true); //bool ufcsExpansionsfalse,

	HRESULT hr;
	hr = srv.ConfigureSemanticProject(filename, imp, empty, empty, empty, flags);
	assert(hr == S_OK);

	void checkErrors(string src, string expected_err)
	{
		auto source = allocBSTR(src);
		HRESULT hr = srv.UpdateModule(filename, source, false);
		assert(hr == S_OK);
		BSTR errors;
		while (srv.GetParseErrors(filename, &errors) == S_FALSE)
			Thread.sleep(10.msecs);

		string err = detachBSTR(errors);
		assert(err == expected_err);
		freeBSTR(source);
	}

	void checkTip(int line, int col, string expected_tip)
	{
		HRESULT hr = srv.GetTip(filename, line, col, line, col + 1, 0);
		assert(hr == S_OK);
		BSTR bstrTip;
		int startLine, startIndex, endLine, endIndex;
		while (srv.GetTipResult(startLine, startIndex, endLine, endIndex, &bstrTip) == S_FALSE || _stricmp(bstrTip, "__pending__"w) == 0)
		{
			detachBSTR(bstrTip);
			Thread.sleep(10.msecs);
		}

		string tip = detachBSTR(bstrTip);
		assert(tip == expected_tip);
	}

	void checkDefinition(int line, int col, string expected_fname, int expected_line, int expected_col)
	{
		HRESULT hr = srv.GetDefinition(filename, line, col, line, col + 1);
		assert(hr == S_OK);
		BSTR bstrFile;
		int startLine, startIndex, endLine, endIndex;
		while (srv.GetDefinitionResult(startLine, startIndex, endLine, endIndex, &bstrFile) == S_FALSE || _stricmp(bstrFile, "__pending__"w) == 0)
		{
			detachBSTR(bstrFile);
			Thread.sleep(10.msecs);
		}

		string file = detachBSTR(bstrFile);
		assert(file == expected_fname);
		assert(startLine == expected_line);
		assert(startIndex == expected_col);
	}

	string source;
/+
	source = q{
		int main()
		{
			return abc;
		}
	};
	checkErrors(source, "4,10,4,11:undefined identifier `abc`\n");

	GC.collect();

	source = q{
		int main()
		{
			return abcd;
		}
	};
	checkErrors(source, "4,10,4,11:undefined identifier `abcd`\n");
+/
	version(traceGC)
		wipeStack();
	GC.collect();

	//_CrtDumpMemoryLeaks();
	version(traceGC)
		dumpGC();

	for (int i = 0; i < 2; i++)
	{
		srv.mModules = null;
		srv.mErrors = null;
		clearDmdStatics ();

		source = q{
			import std.stdio;
			int main(string[] args)
			{
				int xyz = 7;
				writeln(1, 2, 3);
				return xyz;
			}
		};
		checkErrors(source, "");

		version(traceGC)
			wipeStack();
		GC.collect();

		//_CrtDumpMemoryLeaks();
		version(traceGC)
			dumpGC();
	}

	checkTip(5, 9, "(local variable) int xyz");
	checkTip(6, 9, "void std.stdio.writeln!(int, int, int).writeln(int _param_0, int _param_1, int _param_2) @safe");
	checkTip(7, 12, "(local variable) int xyz");

	version(traceGC)
		wipeStack();
	GC.collect();

	checkDefinition(7, 12, "source.d", 5, 9); // xyz
}
