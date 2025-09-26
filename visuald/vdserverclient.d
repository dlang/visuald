// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.vdserverclient;

import visuald.dpackage;
import visuald.pkgutil;
import visuald.logutil;

import vdc.ivdserver;
//import vdc.semantic;
import vdc.util;

import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;
import sdk.vsi.sdk_shared;

import sdk.port.base;

import stdext.com;
import stdext.container;
import stdext.string;

import std.concurrency;
import std.datetime;
import std.string;
import std.conv;
import std.path;
import std.windows.charset;
import core.atomic;
import core.thread;

alias object.AssociativeArray!(string, std.concurrency.Tid) _wa1; // fully instantiate type info for string[Tid]
alias object.AssociativeArray!(std.concurrency.Tid, string[]) _wa2; // fully instantiate type info for string[Tid]

// version(TESTMAIN) version = InProc;
version = DebugCmd;
// debug version = InProc;

version(InProc) import vdc.vdserver;

///////////////////////////////////////////////////////////////////////
version(DebugCmd)
{
import std.datetime;
import core.stdc.stdio : fprintf, snprintf, fopen, fflush, fputc, FILE;
__gshared FILE* dbgfh;
__gshared bool dbgfh_failed;
__gshared bool dbglog_enabled;

private void dbglog(string s)
{
	char[40] strtm;
	SysTime now = Clock.currTime();
	auto len = snprintf(strtm.ptr, 40, "%02d:%02d:%02d.%03d ",
					    now.hour, now.minute, now.second, cast(int)now.fracSecs.total!"msecs");
	debug
	{
		version(all)
			logCall("VDClient: %s", s);
		else
			OutputDebugStringA(toMBSz("VDClient: " ~ s ~ "\n"));
	}
	else if (!dbgfh_failed)
	{
		if(!dbgfh)
		{
			import std.file;
			string fname = tempDir() ~ "/dmdserver";
			char[20] name = "/vdclient0.log";
			for (char i = '0'; !dbgfh && i <= '9'; i++)
			{
				name[9] = i;
				dbgfh = fopen((fname ~ name).ptr, "w");
			}
			if (!dbgfh)
			{
				dbgfh_failed = true;
				return;
			}
		}
		uint tid = sdk.win32.winbase.GetCurrentThreadId();
		fprintf(dbgfh, "%s - %04x - ", strtm.ptr, tid);
		fprintf(dbgfh, "%.*s", cast(int)s.length, s.ptr);
		fputc('\n', dbgfh);
		fflush(dbgfh);
	}
	writeToBuildOutputPane(cast(string)(strtm[0..len] ~ firstLine(s) ~ "\n"), false);
}
}

///////////////////////////////////////////////////////////////////////
// can be changed through registry entry
// debug version = DebugServer;
version(DebugServer)
	const GUID VDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9A02-7e4ad4084715");
else

	const GUID VDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9902-7e4ad4084715");
version(DebugServer)
	const GUID DParserClassFactory_iid  = uuid("002a2de9-8bb6-484d-AB05-7e4ad4084715"); // needs VDServer, not factory
else
	const GUID DParserClassFactory_iid  = uuid("002a2de9-8bb6-484d-AA05-7e4ad4084715"); // needs VDServer, not factory
const GUID DMDServerClassFactory_iid = uuid("002a2de9-8bb6-484d-9906-7e4ad4084715");

__gshared GUID gServerClassFactory_iid = VDServerClassFactory_iid;
__gshared GUID IVDServer_iid = IVDServer.iid;

__gshared IClassFactory gVDClassFactory;
__gshared IVDServer gVDServer;

bool startVDServer()
{
	if(gVDServer)
		return false;

	CoInitialize(null);

	version(InProc)
		gVDServer = addref(newCom!VDServer);
	else
	{
		GUID factory_iid = IID_IClassFactory;
		HRESULT hr = CoGetClassObject(gServerClassFactory_iid, CLSCTX_LOCAL_SERVER|CLSCTX_INPROC_SERVER, null, factory_iid, cast(void**)&gVDClassFactory);
		if(FAILED(hr))
			return false;

		hr = gVDClassFactory.CreateInstance(null, &IVDServer_iid, cast(void**)&gVDServer);
		if (FAILED(hr))
		{
			gVDClassFactory = release(gVDClassFactory);
			return false;
		}
	}
	version(DebugCmd) if (dbglog_enabled)
		dbglog("VDServer startet successfully");
	return true;
}

bool stopVDServer()
{
	if(!gVDServer)
		return false;

	version(DebugCmd) if (dbglog_enabled)
		dbglog("stopping VDServer");
	gVDServer = release(gVDServer);
	gVDClassFactory = release(gVDClassFactory);

	CoUninitialize();
	return true;
}

void setVDServerLogging(bool log)
{
	dbglog_enabled = log;
}

///////////////////////////////////////////////////////////////////////
struct FileCacheData
{
	TextPos[] binaryIsIn;

	int mParseRequestCount;
	int mParseDoneCount;
}

class ServerCache
{
	FileCacheData[string] mCache;
}

///////////////////////////////////////////////////////////////////////
template _shared(T)
{
	alias T _shared;
	// alias shared(T) _shared;
}

/*shared*/ class Command
{
	this(string cmd)
	{
		version(DebugCmd)
			mCommand = cmd;
		mRequest = sLastRequest.atomicOp!"+="(1);
	}

	// called from clientLoop (might block due to server garbage collecting)
	HRESULT exec() const
	{
		assert(false);
	}
	// polled from clientLoop (might block due to server garbage collecting)
	HRESULT answer()
	{
		return S_OK;
	}
	// called from onIdle
	bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand);
		return true;
	}

	void send(Tid id)
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " send: " ~ mCommand);

		.send(id, cast(size_t) cast(void*) this);
//		.send(id, cast(shared)this);
//		.send(id, this);
	}

	static shared uint sLastRequest;

	uint mRequest;
	version(DebugCmd)
		string mCommand;
}

class ExitCommand : Command
{
	this()
	{
		super("exit");
	}

	override HRESULT exec() const
	{
		stopVDServer();
		return S_OK;
	}
}

class ClearProjectCommand : Command
{
	this()
	{
		super("ClearProject");
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;
		return gVDServer.ClearSemanticProject();
	}
}

class ConfigureCommentTasksCommand : Command
{
	string[] mTokens;

	this(string[] tokens)
	{
		super("ConfigureCommentTasks");
		mTokens = tokens;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;
		string tokens = std.string.join(mTokens, "\n");
		auto btokens = allocBSTR(tokens);
		HRESULT res = gVDServer.ConfigureCommentTasks(btokens);
		freeBSTR(btokens);
		return res;
	}
}

class FileCommand : Command
{
	this(string cmd, string filename)
	{
		version(DebugCmd) cmd ~= " " ~ baseName(filename);
		super(cmd);
		mFilename = filename;
	}

	string mFilename;
}

//////////////////////////////////////

class ConfigureProjectCommand : FileCommand
{
	this(string filename, immutable(string[]) imp, immutable(string[]) stringImp,
		 immutable(string[]) versionids, immutable(string[]) debugids,
		 string cmdline, uint flags)
	{
		super("ConfigureProject", filename);
		mImp = imp;
		mStringImp = stringImp;
		mVersionids = versionids;
		mDebugids = debugids;
		mCmdline = cmdline;
		mFlags = flags;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		string jimp        = std.string.join(cast(string[])(mImp[]), "\n");
		string jstringImp  = std.string.join(cast(string[])(mStringImp[]), "\n");
		string jversionids = std.string.join(cast(string[])(mVersionids[]), "\n");
		string jdebugids   = std.string.join(cast(string[])(mDebugids[]), "\n");

		auto bfilename = allocBSTR(mFilename);
		auto bimp = allocBSTR(jimp);
		auto bstringImp = allocBSTR(jstringImp);
		auto bversionids = allocBSTR(jversionids);
		auto bdebugids = allocBSTR(jdebugids);
		auto bcmdline = allocBSTR(mCmdline);

		HRESULT hr = gVDServer.ConfigureSemanticProject(bfilename, bimp, bstringImp, bversionids, bdebugids, bcmdline, mFlags);

		freeBSTR(bfilename);
		freeBSTR(bimp);
		freeBSTR(bstringImp);
		freeBSTR(bversionids);
		freeBSTR(bdebugids);
		freeBSTR(bcmdline);

		return hr;
	}

	immutable(string[]) mImp;
	immutable(string[]) mStringImp;
	immutable(string[]) mVersionids;
	immutable(string[]) mDebugids;
	string mCmdline;
	uint mFlags;
}

//////////////////////////////////////

alias void delegate(uint request, string fname, string type, sdk.vsi.sdk_shared.TextSpan span) GetTipCallBack;

class GetTipCommand : FileCommand
{
	this(string filename, sdk.vsi.sdk_shared.TextSpan span, int flags, GetTipCallBack cb)
	{
		super("GetTip", filename);
		version(DebugCmd) mCommand ~= " {" ~ to!string(span.iStartLine) ~ "," ~ to!string(span.iStartIndex)
			~ " - " ~ to!string(span.iEndLine) ~ "," ~ to!string(span.iEndIndex) ~ "}";
		mSpan = span;
		mFlags = flags;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		int iStartLine = mSpan.iStartLine + 1;
		int iStartIndex = mSpan.iStartIndex;
		int iEndLine = mSpan.iEndLine + 1;
		int iEndIndex = mSpan.iEndIndex;
		HRESULT rc = gVDServer.GetTip(fname, iStartLine, iStartIndex, iEndLine, iEndIndex, mFlags);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR btype;
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		HRESULT rc = gVDServer.GetTipResult(iStartLine, iStartIndex, iEndLine, iEndIndex, &btype);
		if(rc != S_OK)
			return rc;

		mType = detachBSTR(btype);
		mSpan = sdk.vsi.sdk_shared.TextSpan(iStartIndex, iStartLine - 1, iEndIndex, iEndLine - 1);

		if (mType == "__pending__")
			return E_PENDING;
		if (mType == "__cancelled__")
			return ERROR_CANCELLED;

		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand ~ " " ~ ": " ~ mType);
		if(mCallback)
			mCallback(mRequest, mFilename, mType, mSpan);
		return true;
	}

	GetTipCallBack mCallback;
	sdk.vsi.sdk_shared.TextSpan mSpan;
	int mFlags;
	string mType;
}

//////////////////////////////////////

alias void delegate(uint request, string fname, sdk.vsi.sdk_shared.TextSpan span) GetDefinitionCallBack;

class GetDefinitionCommand : FileCommand
{
	this(string filename, sdk.vsi.sdk_shared.TextSpan span, GetDefinitionCallBack cb)
	{
		super("GetDefinition", filename);
		version(DebugCmd) mCommand ~= " {" ~ to!string(span.iStartLine) ~ "," ~ to!string(span.iStartIndex)
			~ " - " ~ to!string(span.iEndLine) ~ "," ~ to!string(span.iEndIndex) ~ "}";
		mSpan = span;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		int iStartLine = mSpan.iStartLine + 1;
		int iStartIndex = mSpan.iStartIndex;
		int iEndLine = mSpan.iEndLine + 1;
		int iEndIndex = mSpan.iEndIndex;
		HRESULT rc = gVDServer.GetDefinition(fname, iStartLine, iStartIndex, iEndLine, iEndIndex);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname;
		int iStartLine, iStartIndex, iEndLine, iEndIndex;
		HRESULT rc = gVDServer.GetDefinitionResult(iStartLine, iStartIndex, iEndLine, iEndIndex, &fname);
		if(rc != S_OK)
			return rc;

		mDefFile = detachBSTR(fname);
		mSpan = sdk.vsi.sdk_shared.TextSpan(iStartIndex, iStartLine - 1, iEndIndex, iEndLine - 1);

		if (mDefFile == "__pending__")
			return E_PENDING;
		if (mDefFile == "__cancelled__")
			return ERROR_CANCELLED;

		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand ~ " " ~ ": " ~ mDefFile);
		if(mCallback)
			mCallback(mRequest, mDefFile, mSpan);
		return true;
	}

	GetDefinitionCallBack mCallback;
	sdk.vsi.sdk_shared.TextSpan mSpan;
	string mDefFile;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string parseErrors,
                    TextPos[] binaryIsIn, string tasks, string outline, string idTypes, ParameterStorageLoc[] stcLocs) UpdateModuleCallBack;

__gshared uint[string] gLastModuleUpdates;
shared(Object) gSyncLastModuleUpdates = new Object;

class UpdateModuleCommand : FileCommand
{
	this(string filename, wstring text, bool verbose, UpdateModuleCallBack cb)
	{
		super("UpdateModule", filename);
		mText = text;
		mCallback = cb;
		mVerbose = verbose;
		synchronized(gSyncLastModuleUpdates)
			gLastModuleUpdates[mFilename] = mRequest;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		synchronized(gSyncLastModuleUpdates)
			if (gLastModuleUpdates[mFilename] != mRequest)
				return ERROR_CANCELLED;

		BSTR bfname = allocBSTR(mFilename);

		BSTR btxt = allocwBSTR(mText);
		DWORD flags = (mVerbose ? 1 : 0);
		HRESULT hr = gVDServer.UpdateModule(bfname, btxt, flags);
		freeBSTR(btxt);
		freeBSTR(bfname);
		return hr;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		synchronized(gSyncLastModuleUpdates)
			if (gLastModuleUpdates[mFilename] != mRequest)
				return ERROR_CANCELLED;

		BSTR fname = allocBSTR(mFilename);
		scope(exit) freeBSTR(fname);
		BSTR errors;
		if(auto hr = gVDServer.GetParseErrors(fname, &errors))
			return hr;

		mErrors = detachBSTR(errors);

		void variantToArray(size_t function(size_t) reorder = n => n, A)(ref VARIANT locs, ref A a)
		{
			if (locs.vt == (VT_ARRAY | VT_INT) || locs.vt == (VT_ARRAY | VT_I4))
			{
				SAFEARRAY* sa = locs.parray;
				assert(SafeArrayGetDim(sa) == 1);
				LONG lbound, ubound;
				SafeArrayGetLBound(sa, 1, &lbound);
				SafeArrayGetUBound(sa, 1, &ubound);

				enum Alen = a[0].tupleof.length;
				size_t cnt = (ubound - lbound + 1) / Alen;
				a.length = cnt;
				LONG index = lbound;
				int val;
				for(size_t i = 0; i < cnt; i++)
				{
					static foreach(f; 0..Alen)
					{
						SafeArrayGetElement(sa, &index, &val);
						a[i].tupleof[reorder(f)] = val;
						index++;
					}
				}
				SafeArrayDestroy(sa);
			}
		}

		VARIANT locs;
		if(gVDServer.GetBinaryIsInLocations(fname, &locs) == S_OK)
			variantToArray!(n => 1 - n)(locs, mBinaryIsIn); // swap line and column

		BSTR tasks;
		if(gVDServer.GetCommentTasks(fname, &tasks) == S_OK)
			mTasks = detachBSTR(tasks);

		BSTR outline;
		if(gVDServer.GetDocumentOutline(fname, &outline) == S_OK)
			mOutline = detachBSTR(outline);

		if (Package.GetGlobalOptions().showParamStorage)
		{
			VARIANT stclocs;
			if(gVDServer.GetParameterStorageLocs(fname, &stclocs) == S_OK)
				variantToArray(stclocs, mParameterStcLocs);
		}
		if (Package.GetGlobalOptions().semanticHighlighting)
		{
			int flags = 2 | (Package.GetGlobalOptions().semanticResolveFields ? 1 : 0);
			if (gVDServer.GetIdentifierTypes(fname, 0, -1, flags) == S_OK)
			{
				BSTR types;
				if(gVDServer.GetIdentifierTypesResult(&types) == S_OK)
					mIdentifierTypes = detachBSTR(types);
			}
		}
		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand ~ " " ~ ": " ~ mErrors);
		if(mCallback)
			mCallback(mRequest, mFilename, mErrors, cast(TextPos[])mBinaryIsIn, mTasks,
					  mOutline, mIdentifierTypes, mParameterStcLocs);
		return true;
	}

	UpdateModuleCallBack mCallback;
	wstring mText;
	string mErrors;
	string mTasks;
	string mOutline;
	string mIdentifierTypes;
	bool mVerbose;
	TextPos[] mBinaryIsIn;
	ParameterStorageLoc[] mParameterStcLocs;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string identifierTypes) GetIdentifierTypesCallBack;

class GetIdentifierTypesCommand : FileCommand
{
	this(string filename, int startLine, int endLine, bool resolve, GetIdentifierTypesCallBack cb)
	{
		super("GetIdentifierTypes", filename);
		version(DebugCmd) mCommand ~= " " ~ to!string(startLine) ~ "-" ~ to!string(endLine);
		mStartLine = startLine;
		mEndLine = endLine;
		mResolve = resolve;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR bfname = allocBSTR(mFilename);
		DWORD flags = (mResolve ? 1 : 0);
		HRESULT hr = gVDServer.GetIdentifierTypes(bfname, mStartLine, mEndLine, flags);
		freeBSTR(bfname);
		return hr;
	}

	override HRESULT answer()
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR types;
		if(auto hr = gVDServer.GetIdentifierTypesResult(&types))
			return hr;

		string stypes = detachBSTR(types);
		if (stypes == "__pending__")
			return E_PENDING;
		if (stypes == "__cancelled__")
			return ERROR_CANCELLED;

		mIdentifierTypes = stypes;

		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand ~ " " ~ ": " ~ mIdentifierTypes);
		if(mCallback)
			mCallback(mRequest, mFilename, mIdentifierTypes);
		return true;
	}

	GetIdentifierTypesCallBack mCallback;
	int mStartLine;
	int mEndLine;
	bool mResolve;
	string mIdentifierTypes;
}

//////////////////////////////////////

alias void delegate(uint request, string filename, string tok, int line, int idx, string[] exps) GetExpansionsCallBack;

class GetExpansionsCommand : FileCommand
{
	this(string filename, string tok, int line, int idx, wstring expr, GetExpansionsCallBack cb)
	{
		super("GetExpansions", filename);
		mTok = tok;
		mLine = line;
		mIndex = idx;
		mExpr = expr;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		BSTR tok = allocBSTR(mTok);
		BSTR expr = allocwBSTR(mExpr);
		HRESULT rc = gVDServer.GetSemanticExpansions(fname, tok, mLine + 1, mIndex, expr);
		freeBSTR(expr);
		freeBSTR(tok);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		BSTR stringList;
		HRESULT rc = gVDServer.GetSemanticExpansionsResult(&stringList);
		if(rc != S_OK)
			return rc;

		string slist = detachBSTR(stringList);
		if (slist == "__pending__")
			return E_PENDING;
		if (slist == "__cancelled__")
			return ERROR_CANCELLED;

		mExpansions = /*cast(shared(string[]))*/ splitLines(slist);
		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand ~ " " ~ ": " ~ join(mExpansions, "\n"));
		if(mCallback)
			mCallback(mRequest, mFilename, mTok, mLine, mIndex, cast(string[])mExpansions);
		return true;
	}

	GetExpansionsCallBack mCallback;
	string mTok;
	wstring mExpr;
	int mLine;
	int mIndex;
	string[] mExpansions;
}

///////////////////////////////////////
alias void delegate(uint request, string filename, string tok, int line, int idx, string[] exps) GetReferencesCallBack;

class GetReferencesCommand : FileCommand
{
	this(string filename, string tok, int line, int idx, wstring expr, bool moduleOnly, GetReferencesCallBack cb)
	{
		super("GetReferences", filename);
		mTok = tok;
		mLine = line;
		mIndex = idx;
		mExpr = expr;
		mModuleOnly = moduleOnly;
		mCallback = cb;
	}

	override HRESULT exec() const
	{
		if(!gVDServer)
			return S_FALSE;

		BSTR fname = allocBSTR(mFilename);
		BSTR tok = allocBSTR(mTok);
		BSTR expr = allocwBSTR(mExpr);
		HRESULT rc = gVDServer.GetReferences(fname, tok, mLine + 1, mIndex, expr, mModuleOnly);
		freeBSTR(expr);
		freeBSTR(tok);
		freeBSTR(fname);
		return rc;
	}

	override HRESULT answer()
	{
		BSTR stringList;
		HRESULT rc = gVDServer.GetReferencesResult(&stringList);
		if(rc != S_OK)
			return rc;

		string slist = detachBSTR(stringList);
		if (slist == "__pending__")
			return E_PENDING;
		if (slist == "__cancelled__")
			return ERROR_CANCELLED;

		mReferences = /*cast(shared(string[]))*/ splitLines(slist);
		send(gUITid);
		return S_OK;
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand ~ " " ~ ": " ~ join(mReferences, "\n"));
		if(mCallback)
			mCallback(mRequest, mFilename, mTok, mLine, mIndex, cast(string[])mReferences);
		return true;
	}

	GetReferencesCallBack mCallback;
	string mTok;
	wstring mExpr;
	int mLine;
	int mIndex;
	int mModuleOnly;
	string[] mReferences;
}


///////////////////////////////////////
class GetMessageCommand : Command
{
	this(string message)
	{
		super("GetMessage");
		mMessage = message;
	}

	override bool forward()
	{
		showStatusBarText(mMessage);
		return true;
	}

	string mMessage;
}

///////////////////////////////////////
class ServerRestartedCommand : Command
{
	this()
	{
		super("ServerRestarted");
	}

	override bool forward()
	{
		version(DebugCmd) if (dbglog_enabled)
			dbglog("#" ~ to!string(mRequest) ~ " fwrd: " ~ mCommand);
		import visuald.dpackage;
		Package.GetLanguageService().RestartParser();
		return true;
	}
}

///////////////////////////////////////////////////////////////////////
__gshared Tid gUITid;

class VDServerClient
{
	Tid mTid;

	this()
	{
	}

	~this()
	{
		shutDown();
	}

	void start()
	{
		gUITid = thisTid();
		mTid = spawn(&clientLoop);
	}

	//////////////////////////////////////
	void shutDown()
	{
		dbglog_enabled = false; // output pane no longer accessible during shutdown
		if(gVDServer)
		{
			(new _shared!(ExitCommand)).send(mTid);
			while(gVDServer)
			{
				Thread.sleep(dur!"msecs"(50));  // sleep for 50 milliseconds
			}
		}
	}

	//////////////////////////////////////
	uint ConfigureSemanticProject(string filename, immutable(string[]) imp, immutable(string[]) stringImp,
								  immutable(string[]) versionids, immutable(string[]) debugids, string cmdline, uint flags)
	{
		auto cmd = new _shared!(ConfigureProjectCommand)(filename, imp, stringImp, versionids, debugids, cmdline, flags);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint GetTip(string filename, sdk.vsi.sdk_shared.TextSpan* pSpan, int flags, GetTipCallBack cb)
	{
		auto cmd = new _shared!(GetTipCommand)(filename, *pSpan, flags, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint GetDefinition(string filename, sdk.vsi.sdk_shared.TextSpan* pSpan, GetDefinitionCallBack cb)
	{
		auto cmd = new _shared!(GetDefinitionCommand)(filename, *pSpan, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	int GetSemanticExpansions(string filename, string tok, int line, int idx, wstring expr, GetExpansionsCallBack cb)
	{
		auto cmd = new _shared!(GetExpansionsCommand)(filename, tok, line, idx, expr, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	int GetReferences(string filename, string tok, int line, int idx, wstring expr, bool moduleOnly, GetReferencesCallBack cb)
	{
		auto cmd = new _shared!(GetReferencesCommand)(filename, tok, line, idx, expr, moduleOnly, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	int GetIdentifierTypes(string filename, int startLine, int endLine, bool resolve, GetIdentifierTypesCallBack cb)
	{
		auto cmd = new _shared!(GetIdentifierTypesCommand)(filename, startLine, endLine, resolve, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint UpdateModule(string filename, wstring text, bool verbose, UpdateModuleCallBack cb)
	{
		auto cmd = new _shared!(UpdateModuleCommand)(filename, text, verbose, cb);
		cmd.send(mTid);
		return cmd.mRequest;
	}
	uint ClearSemanticProject()
	{
		auto cmd = new _shared!(ClearProjectCommand);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	uint ConfigureCommentTasks(string[] tokens)
	{
		auto cmd = new _shared!(ConfigureCommentTasksCommand)(tokens);
		cmd.send(mTid);
		return cmd.mRequest;
	}

	//////////////////////////////////////
	// obsolete
	bool isBinaryOperator(string filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		return false;
	}
	bool _isBinaryOperator(string filename, int startLine, int startIndex, int endLine, int endIndex)
	{
		if(!gVDServer)
			return false;

		BOOL res;
		BSTR fname = allocBSTR(filename);
		HRESULT rc = gVDServer.IsBinaryOperator(fname, startLine, startIndex, endLine, endIndex, &res);
		freeBSTR(fname);
		return rc == S_OK && res != 0;
	}

	bool GetParseErrors(string filename, ref string err)
	{
		return false;
	}
	bool _GetParseErrors(string filename, ref string err)
	{
		if(!gVDServer)
			return false;

		BSTR fname = allocBSTR(filename);
		scope(exit) freeBSTR(fname);
		BSTR errors;
		if(gVDServer.GetParseErrors(fname, &errors) != S_OK)
			return false;
		err = detachBSTR(errors);
		return true;
	}

	//////////////////////////////////////
	static shared bool restartServer = false;

	static void clientLoop()
	{
		if (!startVDServer())
			restartServer = true;

		try
		{
			SysTime lastAnswerTime = Clock.currTime();
			bool pendingMessageSent = false;

			Queue!(_shared!(Command)) toAnswer;
			while(gVDServer || restartServer)
			{
				bool changed = false;
				receiveTimeout(dur!"msecs"(50),
					// as of dmd 2.060, fixes of const handling expose that std.variant is not capable of working sensibly with class objects
					//(shared(Command) icmd)
				    (size_t icmd)
					{
						auto cmd = cast(Command) cast(void*) icmd;
						version(DebugCmd) if (dbglog_enabled)
							dbglog("#" ~ to!string(cmd.mRequest) ~ " exec: " ~ cmd.mCommand);
						HRESULT hr = cmd.exec();
						if(hr == S_OK)
							toAnswer ~= cmd;
						else if((hr & 0xffff) == RPC_S_SERVER_UNAVAILABLE)
							restartServer = true;
						else
							version(DebugCmd) if (dbglog_enabled)
								dbglog("#" ~ to!string(cmd.mRequest) ~ " skip: " ~ cmd.mCommand);
						changed = true;
					},
					(Variant var)
					{
						Variant var2 = var;
					}
				);
				for(int i = 0; i < toAnswer.length && !restartServer; )
				{
					auto cmd = toAnswer[i];
					HRESULT hr = cmd.answer();
					if(hr == S_OK || hr == ERROR_CANCELLED)
					{
						version(DebugCmd) if (dbglog_enabled && hr == ERROR_CANCELLED)
							dbglog("#" ~ to!string(cmd.mRequest) ~ " cncl: " ~ cmd.mCommand);
						toAnswer.remove(i);
						changed = true;
						lastAnswerTime = Clock.currTime();
					}
					else if (hr == E_PENDING)
						break;
					else if((hr & 0xffff) == RPC_S_SERVER_UNAVAILABLE)
						restartServer = true;
					else
						i++;
				}

				BSTR msg;
				if(gVDServer && !restartServer)
				{
					HRESULT hr = gVDServer.GetLastMessage(&msg);
					if(hr == S_OK)
					{
						string m = detachBSTR(msg);
						if(m != "__no_message__")
						{
							(new _shared!(GetMessageCommand)(m)).send(gUITid);
							pendingMessageSent = false;
						}
						else if (toAnswer.length > 0 && lastAnswerTime + 2.seconds < Clock.currTime())
						{
							(new _shared!(GetMessageCommand)("Pending semantic analysis request...")).send(gUITid);
							lastAnswerTime = Clock.currTime();
							pendingMessageSent = true;
						}
						else if (toAnswer.length == 0 && pendingMessageSent)
						{
							(new _shared!(GetMessageCommand)("")).send(gUITid);
							pendingMessageSent = false;
						}
					}
					else if((hr & 0xffff) == RPC_S_SERVER_UNAVAILABLE)
						restartServer = true;
				}

				version(DebugCmd) if (dbglog_enabled) if (changed)
				{
					string s = "   answerQ = [";
					for(int i = 0; i < toAnswer.length; i++)
						s ~= (i > 0 ? " " : "") ~ to!string(toAnswer[i].mRequest);
					dbglog(s ~ "]");
				}
				if(restartServer)
				{
					restartServer = false;
					version(DebugCmd) if (dbglog_enabled)
						dbglog("*** clientLoop: restarting server ***");
					stopVDServer();
					toAnswer.clear();
					if (startVDServer())
						(new _shared!(ServerRestartedCommand)()).send(gUITid);
					else
						restartServer = true;
				}
			}
		}
		catch(Throwable e)
		{
			version(DebugCmd) if (dbglog_enabled)
				dbglog ("clientLoop exception: " ~ e.msg);
		}
		stopVDServer();
	}

	void onIdle()
	{
		try
		{
			while(receiveTimeout(dur!"msecs"(0),
				//(shared(Command) icmd)
				(size_t icmd)
				{
					auto cmd = cast(Command) cast(void*) icmd;
					cmd.forward();
				},
				(Variant var)
				{
					Variant var2 = var;
				}
			))
			{
			}
		}
		catch(Throwable e)
		{
			version(DebugCmd) if (dbglog_enabled)
				dbglog("clientLoop exception: " ~ e.msg);
		}
	}
}
