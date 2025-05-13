// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver.dmdserver;
import vdc.dmdserver.dmdinit;
import vdc.dmdserver.dmderrors;
import vdc.dmdserver.semvisitor;
import vdc.dmdserver.semanalysis;

version(MAIN) {} else version = noServer;
// debug version = traceGC;
version = SingleThread;

version(noServer):
import vdc.ivdserver;

import dmd.arraytypes;
import dmd.cond;
import dmd.dmodule;
import dmd.dsymbolsem;
import dmd.errors;
import dmd.globals;
import dmd.identifier;
import dmd.location;
import dmd.semantic2;
import dmd.semantic3;

import dmd.root.file;
import dmd.root.rmem;

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
import stdext.path;

//import std.stdio;
import std.ascii;
import std.file;
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
import core.stdc.wchar_;

version (traceGC) import tracegc;

version = DebugServer;
// debug version = vdlog; // log through visual D logging (needs version = InProc in vdserverclient)

shared(Object) gDMDSync = new Object; // no multi-instances/multi-threading with DMD
shared(Object) gOptSync = new Object; // no multi-instances/multi-threading with DMD

version (traceGC)
	extern(C) __gshared string[] rt_options = [ "scanDataSeg=precise", "gcopt=gc:trace disable:0" ];
else
	// precise GC doesn't help much because dmd erases most type info
	extern(C) __gshared string[] rt_options = [ "scanDataSeg=precise", "gcopt=gc:precise heapSizeFactor=1.1" ];

///////////////////////////////////////////////////////////////////////
version(DebugServer)
{
	import std.windows.charset;
	import std.datetime;
	version(vdlog) debug import visuald.logutil;
	import core.stdc.stdio : fprintf, fopen, fputc, fflush, FILE;
	__gshared FILE* dbgfh;
	__gshared bool dbgfh_failed;

	void dbglog(const(char)[] s)
	{
		version(none) //debug
		{
			version(vdlog)
				logCall("DMDServer: ", s);
			else
				sdk.win32.winbase.OutputDebugStringA(toMBSz("DMDServer: " ~ s ~ "\n"));
		}
		else
		{
			if(!dbgfh)
			{
				if(!dbgfh_failed)
				{
					uint pid = sdk.win32.winbase.GetCurrentProcessId();
					char[260] tpath;
					auto len = sdk.win32.winbase.GetTempPathA(260, tpath.ptr);
					sprintf(tpath.ptr + len, "dmdserver\\dmdserver-%d.log", pid);
					dbgfh = fopen(tpath.ptr, "w");
				}
				if(!dbgfh)
				{
					dbgfh_failed = true;
					return;
				}
				fprintf(dbgfh, "================================================\n");
			}

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

///////////////////////////////////////////////////////////////
enum ModuleState
{
	New,
	Pending,
	Parsing,
	Analyzing,
	Done
}

struct ModuleData
{
	string filename;
	Module parsedModule;
	Module analyzedModule;

	ModuleState state;
	string parseErrors;
	string analyzeErrors;
}

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
		dmdInit();
		dbglog("Server started");
	}

	override ULONG Release()
	{
		version(SingleThread)
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

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
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
				version(DebugServer) if(dbgfh) dbglog("taskLoop exception: " ~ e.toString());
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

	override HRESULT ConfigureSemanticProject(in BSTR filename, in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, in BSTR cmdline, DWORD flags)
	{
		string fname = to_string(filename);

		synchronized(gOptSync)
		{
			auto opts = &mOptions;

			string imports = to_string(imp);
			string strImports = to_string(stringImp);

			uint oldflags = ConfigureFlags!()(opts.unittestOn, opts.debugOn, opts.x64,
											  opts.coverage, opts.doDoc, opts.noBoundsCheck, opts.gdcCompiler,
											  0, 0, // no need to compare version levels, done in setVersionIds
											  opts.noDeprecated, opts.deprecatedInfo,
											  opts.ldcCompiler, opts.msvcrt, opts.warnings, opts.warnAsError,
											  opts.mixinAnalysis, opts.UFCSExpansions);

			opts.unittestOn     = (flags & 1) != 0;
			opts.debugOn        = (flags & 2) != 0;
			opts.x64            = (flags & 4) != 0;
			opts.coverage       = (flags & 8) != 0;
			opts.doDoc          = (flags & 16) != 0;
			opts.noBoundsCheck  = (flags & 32) != 0;
			opts.gdcCompiler    = (flags & 64) != 0;
			opts.noDeprecated   = (flags & 128) != 0;
			opts.deprecatedInfo = (flags & 0x40_00_00_00) != 0;
			opts.mixinAnalysis  = (flags & 0x1_00_00_00) != 0;
			opts.UFCSExpansions = (flags & 0x2_00_00_00) != 0;
			opts.ldcCompiler    = (flags & 0x4_00_00_00) != 0;
			opts.msvcrt         = (flags & 0x8_00_00_00) != 0;
			opts.warnings       = (flags & 0x10_00_00_00) != 0;
			opts.warnAsError    = (flags & 0x20_00_00_00) != 0;

			int versionlevel = (flags >> 8)  & 0xff;
			int debuglevel   = (flags >> 16) & 0xff;

			string verids = to_string(versionids);
			string dbgids = to_string(debugids);
			string cmdln  = to_string(cmdline);

			int changed = (oldflags != (flags & 0xff0000ff)) + (cmdln != opts.cmdline);
			opts.cmdline = cmdln;
			changed += opts.setImportDirs(splitLines(imports));
			changed += opts.setStringImportDirs(splitLines(strImports));
			changed += opts.setVersionIds(versionlevel, splitLines(verids));
			changed += opts.setDebugIds(debuglevel, splitLines(dbgids));

			long res;
			auto p = opts.cmdline.indexOf(" -memThreshold=");
			const(char)[] arg = p >= 0 ? opts.cmdline[p + 15..$] : "0";
			opts.restartMemThreshold = parseLong(arg, res) ? cast(uint)res : 0;
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

	extern(D) static void tryExec(void delegate() dg)
	{
		try
		{
			import core.exception;
			debug assertHandler(function(string file, ulong line, string msg){
				throw new AssertError(msg, file, line);
			});
			dg();
		}
		catch(Exception e)
		{
			version(DebugServer) if(dbgfh) dbglog("UpdateModule.doParse: exception " ~ e.toString());
		}
		catch(OutOfMemoryError oom)
		{
			exit(33); // throw oom; // terminate
		}
		catch(Throwable t)
		{
			version(DebugServer) if(dbgfh) dbglog("UpdateModule.doParse: error " ~ t.toString());
			if (t.msg != "cancel malloc" && t.msg != "fatal error") // fatal() is a non-fatal error
				exit(37); // terminate the server and let it be restarted
		}
	}

	override HRESULT UpdateModule(in BSTR filename, in BSTR srcText, in DWORD flags)
	{
		GC.Stats stats;
		if (mOptions.restartMemThreshold &&
			(stats = GC.stats()).usedSize > (mOptions.restartMemThreshold << 20L))
		{
			// throw away everything and restart form scratch
			synchronized(gDMDSync)
			{
				reinitSemanticModules();
				foreach (i, m; mModules)
					m.analyzedModule = null;

				version(traceGC)
				{
					mModules = null;
					check_leaks();
				}
				else
					GC.collect();
			}
		}

		string fname = makeFilenameCanonical(to_string(filename), null);
		size_t len = wcslen(srcText);
		string text  = to_string(srcText, len + 1); // DMD parser needs trailing 0
		text = text[0..$-1];

		ModuleData* modData;
		bool doCancel = false;
		synchronized(gErrorSync)
		{
			// cancel existing
			modData = findModule(fname, false);
			if (modData)
			{
				if (modData.state == ModuleState.Parsing || modData.state == ModuleState.Analyzing)
					doCancel = true;
			}

			// always create new module
			modData = findModule(fname, true);
			modData.state = ModuleState.Pending;
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
			version(DebugServer) if(dbgfh) dbglog("    doParse: " ~ firstLine(text));

			synchronized(gErrorSync)
			{
				modData.state = ModuleState.Parsing;
			}
			synchronized(gDMDSync)
			{
				analyzeModules(modData, fname, text);
			}

			if(flags & 1)
				writeReadyMessage();
		}
		version(DebugServer) if(dbgfh) dbglog("  scheduleParse: " ~ firstLine(text));
		schedule(&doParse);
		return S_OK;
	}

	override HRESULT GetParseErrors(in BSTR filename, BSTR* errors)
	{
		string fname = makeFilenameCanonical(to_string(filename), null);

		if(auto md = findModule(fname, false))
		{
			synchronized(gErrorSync)
			{
				if (md.state == ModuleState.Done)
				{
					string err = md.parseErrors ~ md.analyzeErrors;
					version(DebugServer) if(dbgfh) dbglog("GetParseErrors: " ~ err);

					*errors = allocBSTR(err);
					return S_OK;
				}
			}
		}
		return S_FALSE;
	}

	override HRESULT GetTip(in BSTR filename, int startLine, int startIndex, int endLine, int endIndex, int flags)
	{
		string fname = makeFilenameCanonical(to_string(filename), null);

		mTipSpan.start.line  = startLine;
		mTipSpan.start.index = startIndex;
		mTipSpan.end.line    = endLine;
		mTipSpan.end.index   = endIndex;

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md)
				return S_FALSE;
		}

		void _getTip()
		{
			string txt;
			synchronized(gDMDSync)
			{
				try
				{
					bool addlinks = (flags & 8) != 0;
					bool addsize = (flags & 16) != 0;
					if (auto m = ensureAnalyzed(md))
						txt = findTip(m, startLine, startIndex + 1, endLine, endIndex + 1, addlinks, addsize);
					else
						txt = "analyzing...";
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) if(dbgfh) dbglog("GetTip: exception " ~ t.toString());
					txt = "exception: " ~ t.msg;
				}
			}
			mLastTip = txt;
			mSemanticTipRunning = false;
		}
		version(DebugServer) if(dbgfh) dbglog("  schedule GetTip: " ~ fname);
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

		version(DebugServer) if(dbgfh) dbglog("GetTipResult: " ~ mLastTip);
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
		string fname = makeFilenameCanonical(to_string(filename), null);

		mDefSpan.start.line  = startLine;
		mDefSpan.start.index = startIndex + 1;
		mDefSpan.end.line    = endLine;
		mDefSpan.end.index   = endIndex; // last character preferred position for evaluation

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md)
				return S_FALSE;
		}

		void _getDefinition()
		{
			string deffilename;
			synchronized(gDMDSync)
			{
				try
				{
					if (auto m = ensureAnalyzed(md))
						deffilename = findDefinition(m, mDefSpan.end.line, mDefSpan.end.index);
					else
						deffilename = "analyzing...";
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) if(dbgfh) dbglog("GetDefinition: exception " ~ t.toString());
				}
			}
			mLastDefFile = deffilename;
			mSemanticDefinitionRunning = false;
		}
		version(DebugServer) if(dbgfh) dbglog("  schedule GetDefinition: " ~ fname);
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

		version(DebugServer) if(dbgfh) dbglog("GetDefinitionResult: " ~ mLastDefFile);
		writeReadyMessage();
		startLine  = mDefSpan.end.line;
		startIndex = mDefSpan.end.index - 1;
		endLine    = mDefSpan.end.line;
		endIndex   = mDefSpan.end.index;
		*answer = allocBSTR(mLastDefFile);
		return S_OK;
	}

	override HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx, in BSTR expr)
	{
		string fname = makeFilenameCanonical(to_string(filename), null);

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md)
				return S_FALSE;
		}

		string stok = to_string(tok);
		string sexpr = to_string(expr);
		void _calcExpansions()
		{
			string[] symbols;
			try
			{
				if (auto m = ensureAnalyzed(md))
					symbols = findExpansions(m, line, idx + 1 - cast(int) stok.length, stok);
			}
			catch(OutOfMemoryError e)
			{
				throw e; // terminate
			}
			catch(Throwable t)
			{
				version(DebugServer) if(dbgfh) dbglog("calcExpansions: exception " ~ t.toString());
			}
			mSemanticExpansionsRunning = false;
			mLastSymbols = symbols;
		}
		version(DebugServer) if(dbgfh) dbglog("  schedule GetSemanticExpansions: " ~ fname ~ "(" ~ to!string(line) ~ "," ~ to!string(idx) ~ "): " ~ stok);
		mLastSymbols = null;
		mSemanticExpansionsRunning = true;
		schedule(&_calcExpansions);

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

		version(DebugServer) if(dbgfh) dbglog("GetSemanticExpansionsResult: " ~ slist.data);
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

	override HRESULT GetDocumentOutline(in BSTR filename, BSTR* outline)
	{
		string fname = makeFilenameCanonical(to_string(filename), null);

		synchronized(gErrorSync)
		{
			ModuleData* md = findModule(fname, false);
			if (!md || !md.parsedModule)
				return S_FALSE;

			string[] outlines = getModuleOutline(md.parsedModule, 4);
			string joined = outlines.join("\n");
			*outline = allocBSTR(joined);
		}
		return S_OK;
	}

	override HRESULT GetBinaryIsInLocations(in BSTR filename, VARIANT* locs)
	{
		// array of pairs of DWORD
		string fname = makeFilenameCanonical(to_string(filename), null);

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md || !md.parsedModule)
				return S_FALSE;
		}

		Loc[] locData = findBinaryIsInLocations(md.parsedModule);

		SAFEARRAY *sa = SafeArrayCreateVector(VT_INT, 0, 2 * cast(ULONG) locData.length);
		if(!sa)
			return E_OUTOFMEMORY;

		for(LONG index = 0; index < locData.length; index++)
		{
			LONG idx = index * 2;
			LONG value = locData[index].linnum;
			SafeArrayPutElement(sa, &idx, &value);
			idx++;
			value = locData[index].charnum - 1;
			SafeArrayPutElement(sa, &idx, &value);
		}

		locs.vt = VT_ARRAY | VT_INT;
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

	override HRESULT GetReferences(in BSTR filename, in BSTR tok, uint line, uint idx, in BSTR expr, in BOOL moduleOnly)
	{
		string fname = makeFilenameCanonical(to_string(filename), null);

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md)
				return S_FALSE;
		}

		void _getReferences()
		{
			string references;
			synchronized(gDMDSync)
			{
				try
				{
					if (auto m = ensureAnalyzed(md))
					{
						auto reflocs = findReferencesInModule(m, line, idx + 1);

						char[128] buf;
						foreach (ref r; reflocs)
						{
							int llen = snprintf(buf.ptr, buf.length, "%d,%d,%d,%d:\n",
												r.loc.linnum, r.loc.charnum - 1,
												r.loc.linnum, r.loc.charnum - 1 + r.ident.toString().length);
							references ~= buf[0..llen];
						}
					}
					else
						references = "analyzing...";
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) if(dbgfh) dbglog("GetReferences: exception " ~ t.toString());
				}
			}
			mLastReferences = references;
			mSemanticGetReferencesRunning = false;
		}
		version(DebugServer) if(dbgfh) dbglog("  schedule GetReferences: " ~ fname);
		mSemanticGetReferencesRunning = true;
		schedule(&_getReferences);

		return S_OK;
	}

	override HRESULT GetReferencesResult(BSTR* stringList)
	{
		if(mSemanticGetReferencesRunning)
		{
			*stringList = allocBSTR("__pending__");
			return S_OK;
		}
		version(DebugServer) if(dbgfh) dbglog("GetReferencesResult: " ~ firstLine(mLastReferences) ~ "...");
		*stringList = allocBSTR(mLastReferences);
		return S_OK;
	}

	HRESULT GetIdentifierTypes(in BSTR filename, int startLine, int endLine, int flags)
	{
		string fname = makeFilenameCanonical(to_string(filename), null);

		mIdTypesSpan.start.line  = startLine; // unused so far
		mIdTypesSpan.start.index = 0;
		mIdTypesSpan.end.line    = endLine;
		mIdTypesSpan.end.index   = 0;

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md)
				return S_FALSE;
		}

		void _getIdentifierTypes()
		{
			string identiferTypes;
			synchronized(gDMDSync)
			{
				try
				{
					if (auto m = md.analyzedModule)
					{
						auto res = findIdentifierTypes(m);
						identiferTypes = findIdentifierTypesResultToString(res);
					}
					else
						identiferTypes = "identifying...";
				}
				catch(OutOfMemoryError e)
				{
					throw e; // terminate
				}
				catch(Throwable t)
				{
					version(DebugServer) if(dbgfh) dbglog("GetIdentifierTypes: exception " ~ t.toString());
				}
			}
			mLastIdentifierTypes = identiferTypes;
			mSemanticIdentifierTypesRunning = false;
		}
		version(DebugServer) if(dbgfh) dbglog("  schedule GetIdentifierTypes: " ~ fname);
		mSemanticIdentifierTypesRunning = true;
		schedule(&_getIdentifierTypes);

		return S_OK;
	}

	HRESULT GetIdentifierTypesResult(BSTR* types)
	{
		if(mSemanticIdentifierTypesRunning)
		{
			*types = allocBSTR("__pending__");
			return S_OK;
		}
		version(DebugServer) if(dbgfh) dbglog("GetIdentifierTypesResult: " ~ firstLine(mLastIdentifierTypes) ~ "...");
		*types = allocBSTR(mLastIdentifierTypes);
		return S_OK;
	}

	override HRESULT GetParameterStorageLocs(in BSTR filename, VARIANT* locs)
	{
		// array of pairs of DWORD
		string fname = makeFilenameCanonical(to_string(filename), null);

		ModuleData* md;
		synchronized(gErrorSync)
		{
			md = findModule(fname, false);
			if (!md || !md.analyzedModule)
			{
				version(DebugServer) if(dbgfh) dbglog("GetParameterStorageLocs: " ~ fname ~ " not found");
				return S_FALSE;
			}
		}

		auto stcLoc = findParameterStorageClass(md.analyzedModule);

		SAFEARRAY *sa = SafeArrayCreateVector(VT_INT, 0, 3 * cast(ULONG) stcLoc.length);
		if(!sa)
		{
			version(DebugServer) if(dbgfh) dbglog("GetParameterStorageLocs: " ~ fname ~ " out of memory (" ~ to!string(stcLoc.length) ~ " entries)");
			return E_OUTOFMEMORY;
		}

		for(LONG index = 0; index < stcLoc.length; index++)
		{
			LONG idx = index * 3;
			LONG value = stcLoc[index].type;
			SafeArrayPutElement(sa, &idx, &value);
			idx++;
			value = stcLoc[index].line;
			SafeArrayPutElement(sa, &idx, &value);
			idx++;
			value = stcLoc[index].col - 1;
			SafeArrayPutElement(sa, &idx, &value);
		}

		version(DebugServer) if(dbgfh) dbglog("GetParameterStorageLocs: " ~ fname ~ " OK (" ~ to!string(stcLoc.length) ~ " entries)");
		locs.vt = VT_ARRAY | VT_INT;
		locs.parray = sa;
		return S_OK;
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

	// call under gDMDSync lock, do not parse if fname is null
	void analyzeModules(ModuleData* modData, string fname, string text)
	{
		string combinedErrorMessages()
		{
			string msgs = getErrorMessages();
			string otherMessages = getErrorMessages(true);
			if (otherMessages.length)
			{

				ptrdiff_t p = 0;
				for (int i = 0; i < 3 && p >= 0; i++)
					p = otherMessages.indexOf('\n', p);
				if (p >= 0)
					otherMessages = otherMessages[0..p] ~ "...";
				msgs ~= "1,0,1,1: errors in imported modules: " ~ otherMessages.replace("\n", "\a");
			}
			return msgs;
		}

		if (fname)
		{
			tryExec(()
			{
				initErrorMessages(fname);
				modData.parsedModule = createModuleFromText(fname, text);
			});
			modData.parseErrors = combinedErrorMessages();
		}

		modData.state = ModuleState.Analyzing;

		tryExec(()
		{
			if (modData.parsedModule)
			{
				initErrorMessages(modData.parsedModule.srcfile.toString().idup);
				// clear all other semantic modules?
				modData.analyzedModule = analyzeModule(modData.parsedModule, mOptions);
			}
		});
		modData.analyzeErrors = combinedErrorMessages();
		modData.state = ModuleState.Done;
	}

	// call under gDMDSync lock
	Module ensureAnalyzed(ModuleData* modData)
	{
		if (modData.analyzedModule)
			return modData.analyzedModule;
		if (!modData.parsedModule)
			return null;
		if (modData.state == ModuleState.Analyzing)
			return null;
		analyzeModules(modData, null, null);
		return modData.analyzedModule;
	}

private:
	ModuleData* findModule(string fname, bool createNew)
	{
		size_t pos = mModules.length;
		foreach (i, m; mModules)
			if (m.filename == fname)
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

		auto md = new ModuleData;
		md.filename = fname;
		if (pos < mModules.length)
			mModules[pos] = md;
		else
			mModules ~= md;
		return md;
	}

	version(SingleThread) Tid mTid;

	Options mOptions;
	ModuleData*[] mModules;

	bool mSemanticExpansionsRunning;
	bool mSemanticTipRunning;
	bool mSemanticDefinitionRunning;
	bool mSemanticIdentifierTypesRunning;
	bool mSemanticGetReferencesRunning;

	bool mPredefineVersions;

	string mModuleToParse;
	string mLastTip;
	TextSpan mTipSpan;

	string mLastDefFile;
	TextSpan mDefSpan;

	string mLastIdentifierTypes;
	TextSpan mIdTypesSpan;

	string mLastReferences;
	string[] mLastSymbols;
	string mLastMessage;
	string mLastError;
	bool mHadMessage;
	SysTime mNextReadyMessage;
}

////////////////////////////////////////////////////////////////

string idPositionsToString(IdTypePos[] pos)
{
	string ids = pos[0].type.to!string();
	foreach (ref p; pos[1..$])
		ids ~= ";" ~ p.type.to!string() ~ "," ~ p.line.to!string() ~ "," ~ (p.col - 1).to!string();
	return ids;
}

string findIdentifierTypesResultToString(FindIdentifierTypesResult res)
{
	string s;
	foreach(id, pos; res)
	{
		string ids = id.idup ~ ":" ~ idPositionsToString(pos);
		s ~= ids ~ "\n";
	}
	return s;
}

////////////////////////////////////////////////////////////////
void dummy_instantiation_of_cas()
{
	// workaround missing symbol starting with dmd 2.093
	import core.atomic;
	LONG Target, old, Value;
	cas( cast(shared(LONG)*)Target, old, Value );
}

////////////////////////////////////////////////////////////////

extern(C) int _CrtDumpMemoryLeaks();
extern(C) void dumpGC();

////////////////////////////////////////////////////////////////
unittest
{
	//_CrtDumpMemoryLeaks();
	version(traceGC)
		dumpGC();

	DMDServer srv = newCom!DMDServer;
	srv.mPredefineVersions = true;
	srv.mOptions.predefineDefaultVersions = true;
	addref(srv);
	scope(exit) release(srv);

	auto filename = allocBSTR("source.d");
	auto imp = allocBSTR(guessImportPaths().join("\n"));
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
								   false, //bool deprecatedInfo,
								   false, //bool ldc,
								   true,  //bool msvcrt,
								   false, //bool warnings,
								   false, //bool warnAsError,
								   true,  //bool mixinAnalysis,
								   true); //bool ufcsExpansionsfalse,

	HRESULT hr;
	hr = srv.ConfigureSemanticProject(filename, imp, empty, empty, empty, null, flags);
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
		if (expected_tip.endsWith("..."))
			assert(tip.startsWith(expected_tip[0..$-3]));
		else
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
		//clearDmdStatics ();

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

	checkTip(5, 9, "(local variable) `int xyz`");
	checkTip(6, 9, "`void std.stdio.writeln!(int, int, int)(int __param_0, int __param_1, int __param_2) @safe`...");
	checkTip(7, 12, "(local variable) `int xyz`");

	version(traceGC)
		wipeStack();
	GC.collect();

	checkDefinition(7, 12, "source.d", 5, 8); // xyz
}
