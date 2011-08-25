// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.logutil;

import visuald.windows;
import std.format;
import std.utf;
import std.string;
import std.stdio;
import std.conv;
import std.datetime;
import std.array;

import stdcarg = core.stdc.stdarg;
import stdcio = core.stdc.stdio;
// import std.stdarg;

public import std.traits;

version(test) {} else {

import visuald.comutil;
public import visuald.vscommands;

static import dte = sdk.port.dte;

import sdk.win32.oleauto;	
	
import sdk.vsi.textmgr;	
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.vsshell90;
import sdk.vsi.ivssccmanager2;
import sdk.vsi.scguids;
import sdk.vsi.textmgr2;
import sdk.vsi.vssplash;
import sdk.vsi.fpstfmt;
import sdk.vsi.vsshlids;
import sdk.vsi.vsdebugguids;
import sdk.vsi.ocdesign;
import sdk.vsi.ivswebservices;
import sdk.vsi.encbuild;

///////////////////////////////////////////////////////////////

bool _false; // used in assert(false) to avoid semantic change of assert

///////////////////////////////////////////////////////////////

void OutputDebugLog(string msg)
{
	OutputDebugStringA(toStringz(msg));
}

///////////////////////////////////////////////////////////////

T returnError(T)(T err)
{
	logCall(" ERROR %x", err);
	return err;
}

///////////////////////////////////////////////////////////////

const GUID  IID_IManagedObject = { 0xc3fcc19e, 0xa970, 0x11d2, [ 0x8b, 0x5a, 0x00, 0xa0, 0xc9, 0xb7, 0xc9, 0xc4 ] };
const GUID  IID_IRpcOptions = uuid("00000144-0000-0000-C000-000000000046");
const GUID  IID_SolutionProperties = uuid("28f7c3a6-fdc6-11d2-8a61-00c04f682e21");
const GUID  IID_isVCProject = uuid("3990034a-3af2-44c9-bd22-7b10654b5721");
const GUID  IID_GetActiveVCFileConfigurationFromVCFile1 = uuid("694c76bc-3ef4-11d3-b278-0050041db12a");
const GUID  VisualD_LanguageService = uuid("002a2de9-8bb6-484d-9800-7e4ad4084715");

string mixinGUID2string(string T)
{
	return "static if (is(typeof(" ~ T ~ ")     : GUID)) { if(guid == " ~ T ~ ")     return \"" ~ T ~ "\"; }"
	~ "else static if (is(typeof(" ~ T ~ ".iid) : GUID)) { if(guid == " ~ T ~ ".iid) return \"" ~ T ~ "\"; }"
	~ "else static if (is(typeof(IID_" ~ T ~ ") : GUID)) { if(guid == IID_" ~ T ~ ") return \"" ~ T ~ "\"; }"
	~ "else static if (is(typeof(uuid_"~ T ~ ") : GUID)) { if(guid == uuid_"~ T ~ ") return \"" ~ T ~ "\"; }"
	~ "else static assert(0, \"unknown GUID " ~ T ~ "\");";
}

string GUID2utf8(ref GUID guid)
{
	mixin(mixinGUID2string("IUnknown"));
	mixin(mixinGUID2string("IClassFactory"));
	mixin(mixinGUID2string("IMarshal"));
	mixin(mixinGUID2string("IMallocSpy"));
	mixin(mixinGUID2string("IStdMarshalInfo"));
	mixin(mixinGUID2string("IExternalConnection"));
	mixin(mixinGUID2string("IMultiQI"));
	mixin(mixinGUID2string("IEnumUnknown"));
	mixin(mixinGUID2string("IBindCtx"));
	mixin(mixinGUID2string("IEnumMoniker"));
	mixin(mixinGUID2string("IRunnableObject"));
	mixin(mixinGUID2string("IRunningObjectTable"));
	mixin(mixinGUID2string("IPersist"));
	mixin(mixinGUID2string("IPersistStream"));
	mixin(mixinGUID2string("IMoniker"));
	mixin(mixinGUID2string("IROTData"));
	mixin(mixinGUID2string("IEnumString"));
	mixin(mixinGUID2string("ISequentialStream"));
	mixin(mixinGUID2string("IStream"));
	mixin(mixinGUID2string("IEnumSTATSTG"));
	mixin(mixinGUID2string("IStorage"));
	mixin(mixinGUID2string("IPersistFile"));
	mixin(mixinGUID2string("IPersistStorage"));
	mixin(mixinGUID2string("ILockBytes"));
	mixin(mixinGUID2string("IEnumFORMATETC"));
	mixin(mixinGUID2string("IEnumSTATDATA"));
	mixin(mixinGUID2string("IRootStorage"));
	mixin(mixinGUID2string("IAdviseSink"));
	mixin(mixinGUID2string("IAdviseSink2"));
	mixin(mixinGUID2string("IDataObject"));
	mixin(mixinGUID2string("IDataAdviseHolder"));
	mixin(mixinGUID2string("IMessageFilter"));
	mixin(mixinGUID2string("IRpcChannelBuffer"));
	mixin(mixinGUID2string("IRpcProxyBuffer"));
	mixin(mixinGUID2string("IRpcStubBuffer"));
	mixin(mixinGUID2string("IPSFactoryBuffer"));
version(none)
{
//	mixin(mixinGUID2string("IPropertyStorage"));
//	mixin(mixinGUID2string("IPropertySetStorage"));
//	mixin(mixinGUID2string("IEnumSTATPROPSTG"));
//	mixin(mixinGUID2string("IEnumSTATPROPSETSTG"));
	mixin(mixinGUID2string("IFillLockBytes"));
	mixin(mixinGUID2string("IProgressNotify"));
	mixin(mixinGUID2string("ILayoutStorage"));
//	mixin(mixinGUID2string("IRpcChannel"));
//	mixin(mixinGUID2string("IRpcStub"));
	mixin(mixinGUID2string("IStubManager"));
	mixin(mixinGUID2string("IRpcProxy"));
	mixin(mixinGUID2string("IProxyManager"));
	mixin(mixinGUID2string("IPSFactory"));
	mixin(mixinGUID2string("IInternalMoniker"));
	mixin(mixinGUID2string("IDfReserved1"));
	mixin(mixinGUID2string("IDfReserved2"));
	mixin(mixinGUID2string("IDfReserved3"));
	mixin(mixinGUID2string("IStub"));
	mixin(mixinGUID2string("IProxy"));
	mixin(mixinGUID2string("IEnumGeneric"));
	mixin(mixinGUID2string("IEnumHolder"));
	mixin(mixinGUID2string("IEnumCallback"));
	mixin(mixinGUID2string("IOleManager"));
	mixin(mixinGUID2string("IOlePresObj"));
	mixin(mixinGUID2string("IDebug"));
	mixin(mixinGUID2string("IDebugStream"));
	mixin(mixinGUID2string("StdOle"));
	mixin(mixinGUID2string("ICreateTypeInfo"));
	mixin(mixinGUID2string("ICreateTypeInfo2"));
	mixin(mixinGUID2string("ICreateTypeLib"));
	mixin(mixinGUID2string("ICreateTypeLib2"));
	mixin(mixinGUID2string("IDispatch"));
	mixin(mixinGUID2string("IEnumVARIANT"));
	mixin(mixinGUID2string("ITypeComp"));
	mixin(mixinGUID2string("ITypeInfo"));
	mixin(mixinGUID2string("ITypeInfo2"));
	mixin(mixinGUID2string("ITypeLib"));
	mixin(mixinGUID2string("ITypeLib2"));
	mixin(mixinGUID2string("ITypeChangeEvents"));
	mixin(mixinGUID2string("IErrorInfo"));
	mixin(mixinGUID2string("ICreateErrorInfo"));
	mixin(mixinGUID2string("ISupportErrorInfo"));
	mixin(mixinGUID2string("IOleAdviseHolder"));
	mixin(mixinGUID2string("IOleCache"));
	mixin(mixinGUID2string("IOleCache2"));
	mixin(mixinGUID2string("IOleCacheControl"));
	mixin(mixinGUID2string("IParseDisplayName"));
	mixin(mixinGUID2string("IOleContainer"));
	mixin(mixinGUID2string("IOleClientSite"));
	mixin(mixinGUID2string("IOleObject"));
	mixin(mixinGUID2string("IOleWindow"));
	mixin(mixinGUID2string("IOleLink"));
	mixin(mixinGUID2string("IOleItemContainer"));
	mixin(mixinGUID2string("IOleInPlaceUIWindow"));
	mixin(mixinGUID2string("IOleInPlaceActiveObject"));
	mixin(mixinGUID2string("IOleInPlaceFrame"));
	mixin(mixinGUID2string("IOleInPlaceObject"));
	mixin(mixinGUID2string("IOleInPlaceSite"));
	mixin(mixinGUID2string("IContinue"));
	mixin(mixinGUID2string("IViewObject"));
	mixin(mixinGUID2string("IViewObject2"));
	mixin(mixinGUID2string("IEnumOLEVERB"));
}
	mixin(mixinGUID2string("IDropSource"));
	mixin(mixinGUID2string("IDropTarget"));

	mixin(mixinGUID2string("IVsSccManager2"));
	mixin(mixinGUID2string("IVsSccManager3"));
	mixin(mixinGUID2string("IVsSccProject2"));
	mixin(mixinGUID2string("IVsQueryEditQuerySave2"));
	mixin(mixinGUID2string("IVsQueryEditQuerySave3"));
	mixin(mixinGUID2string("IVsTrackProjectDocuments2"));
	mixin(mixinGUID2string("IVsTrackProjectDocuments3"));
	mixin(mixinGUID2string("IVsTrackProjectDocumentsEvents2"));
	mixin(mixinGUID2string("IVsTrackProjectDocumentsEvents3"));
	mixin(mixinGUID2string("IVsSccProviderFactory"));
	mixin(mixinGUID2string("IVsSccProjectProviderBinding"));
	mixin(mixinGUID2string("IVsSccProjectEnlistmentFactory"));
	mixin(mixinGUID2string("IVsSccProjectEnlistmentChoice"));
	mixin(mixinGUID2string("IVsSccEnlistmentPathTranslation"));
	mixin(mixinGUID2string("IVsSccProjectFactoryUpgradeChoice"));

	mixin(mixinGUID2string("SVsSccManager"));
	mixin(mixinGUID2string("SVsQueryEditQuerySave"));
	mixin(mixinGUID2string("SVsTrackProjectDocuments"));

	mixin(mixinGUID2string("IVsLanguageInfo"));
	mixin(mixinGUID2string("IVsLanguageDebugInfo"));
	mixin(mixinGUID2string("IVsProvideColorableItems"));
	mixin(mixinGUID2string("IVsColorableItem"));
	mixin(mixinGUID2string("IVsLanguageContextProvider"));
	mixin(mixinGUID2string("IVsLanguageBlock"));
	mixin(mixinGUID2string("IServiceProvider"));
	mixin(mixinGUID2string("IVsColorizer"));
	mixin(mixinGUID2string("IVsColorizer2"));
	mixin(mixinGUID2string("IVsDebuggerEvents"));
	mixin(mixinGUID2string("IVsDebugger"));
	mixin(mixinGUID2string("IVsFormatFilterProvider"));
	mixin(mixinGUID2string("IVsCodeWindow"));
	mixin(mixinGUID2string("IVsCodeWindowManager"));
	mixin(mixinGUID2string("IVsTextBuffer"));
	mixin(mixinGUID2string("IVsPackage"));
	mixin(mixinGUID2string("IVsInstalledProduct"));
	mixin(mixinGUID2string("IProfferService"));
	mixin(mixinGUID2string("IVsTextLayer"));
	mixin(mixinGUID2string("IVsLanguageTextOps"));
	mixin(mixinGUID2string("IVsTextLines"));
	mixin(mixinGUID2string("IVsTextView"));
	mixin(mixinGUID2string("IVsEnumBSTR"));
	mixin(mixinGUID2string("IVsUserDataEvents"));
	mixin(mixinGUID2string("IVsTextLinesEvents"));
	mixin(mixinGUID2string("IVsTextViewFilter"));
	mixin(mixinGUID2string("IVsTextViewEvents"));
	mixin(mixinGUID2string("IVsExpansionEvents"));
	mixin(mixinGUID2string("IVsOutliningCapableLanguage"));
	mixin(mixinGUID2string("IVsLanguageClipboardOps"));
	mixin(mixinGUID2string("IVsProvideUserContextForObject"));
	mixin(mixinGUID2string("IVsDynamicTabProvider"));
	mixin(mixinGUID2string("IVsAutoOutliningClient"));
	mixin(mixinGUID2string("IVsReadOnlyViewNotification"));
	mixin(mixinGUID2string("IPreferPropertyPagesWithTreeControl"));

	mixin(mixinGUID2string("IVsOutputWindowPane"));
	mixin(mixinGUID2string("IVsProjectFactory"));
	mixin(mixinGUID2string("IVsRegisterProjectTypes"));
	mixin(mixinGUID2string("IVsHierarchy"));
	mixin(mixinGUID2string("IVsUIHierarchy"));
	mixin(mixinGUID2string("IVsOutput"));
	mixin(mixinGUID2string("IVsEnumOutputs"));
	mixin(mixinGUID2string("IVsCfg"));
	mixin(mixinGUID2string("IVsProjectCfg"));
	mixin(mixinGUID2string("IVsProjectCfg2"));
	mixin(mixinGUID2string("IVsBuildableProjectCfg"));
	mixin(mixinGUID2string("IVsBuildableProjectCfg2"));
	mixin(mixinGUID2string("IVsBuildStatusCallback"));
	mixin(mixinGUID2string("IVsDebuggableProjectCfg"));
	mixin(mixinGUID2string("IVsCfgProvider"));
	mixin(mixinGUID2string("IVsProjectCfgProvider"));
	mixin(mixinGUID2string("IVsGetCfgProvider"));
	mixin(mixinGUID2string("IVsProject"));
	mixin(mixinGUID2string("IVsProject2"));
	mixin(mixinGUID2string("IVsProject3"));
	mixin(mixinGUID2string("IVsAggregatableProject"));
	mixin(mixinGUID2string("IVsNonLocalProject"));
	mixin(mixinGUID2string("IVsProjectFlavorCfg"));
	mixin(mixinGUID2string("IPersist"));
	mixin(mixinGUID2string("IPersistFileFormat"));
	mixin(mixinGUID2string("IVsProjectBuildSystem"));
	mixin(mixinGUID2string("IVsBuildPropertyStorage"));
	mixin(mixinGUID2string("IVsComponentUser"));
	mixin(mixinGUID2string("IVsDependencyProvider"));
	mixin(mixinGUID2string("IVsDependency"));
	mixin(mixinGUID2string("IVsEnumDependencies"));
	mixin(mixinGUID2string("IVsProjectSpecialFiles"));
	mixin(mixinGUID2string("IVsHierarchyEvents"));
	mixin(mixinGUID2string("IVsPersistHierarchyItem"));
	mixin(mixinGUID2string("IVsProjectSpecificEditorMap2"));
	mixin(mixinGUID2string("IVsQueryLineChangeCommit"));

	mixin(mixinGUID2string("IVsPersistDocData"));
	mixin(mixinGUID2string("IVsCfgProvider2"));
	mixin(mixinGUID2string("IVsParentProject"));
	mixin(mixinGUID2string("IVsUpdateSolutionEvents"));
	mixin(mixinGUID2string("IVsNonSolutionProjectFactory"));
	mixin(mixinGUID2string("IVsProjectUpgradeViaFactory"));
	mixin(mixinGUID2string("IVsProjectUpgrade"));
	mixin(mixinGUID2string("IVsUpgradeLogger"));
	mixin(mixinGUID2string("IVsProjectUpgradeViaFactory2"));
	mixin(mixinGUID2string("IVsPersistSolutionOpts"));
	mixin(mixinGUID2string("IVsSolutionPersistence"));
	mixin(mixinGUID2string("IVsPersistSolutionProps"));
	mixin(mixinGUID2string("IVsPublishableProjectCfg"));
	mixin(mixinGUID2string("IVsPropertyPageNotify"));
	mixin(mixinGUID2string("IVsPropertyPage"));
	mixin(mixinGUID2string("IVsPropertyPage2"));
	mixin(mixinGUID2string("IVsDeployableProjectCfg"));

	mixin(mixinGUID2string("IConnectionPoint"));
	mixin(mixinGUID2string("IManagedObject"));
	mixin(mixinGUID2string("IProvideClassInfo"));
	mixin(mixinGUID2string("IRpcOptions"));
	mixin(mixinGUID2string("IEnumConnections"));
	mixin(mixinGUID2string("IConnectionPointContainer"));
	mixin(mixinGUID2string("IEnumConnectionPoints"));
	mixin(mixinGUID2string("IOleCommandTarget"));
	mixin(mixinGUID2string("IExtendedObject"));
	mixin(mixinGUID2string("ISpecifyPropertyPages"));
	mixin(mixinGUID2string("ISequentialStream"));
	mixin(mixinGUID2string("IStream"));
	mixin(mixinGUID2string("IPropertyBag"));
	mixin(mixinGUID2string("IErrorLog"));
	mixin(mixinGUID2string("IProvideMultipleClassInfo"));

	mixin(mixinGUID2string("IUseImmediateCommitPropertyPages"));
	mixin(mixinGUID2string("SolutionProperties"));
	mixin(mixinGUID2string("isVCProject"));
	mixin(mixinGUID2string("GetActiveVCFileConfigurationFromVCFile1"));

	mixin(mixinGUID2string("dte._DTE"));
	mixin(mixinGUID2string("dte.Project"));
	mixin(mixinGUID2string("dte.Projects"));
	mixin(mixinGUID2string("dte.ProjectItems"));
	mixin(mixinGUID2string("dte.ProjectItem"));
	mixin(mixinGUID2string("dte.Properties"));
	mixin(mixinGUID2string("dte.Property"));

	mixin(mixinGUID2string("CMDSETID_StandardCommandSet2K"));
	mixin(mixinGUID2string("CMDSETID_StandardCommandSet97"));
	mixin(mixinGUID2string("GUID_VsUIHierarchyWindowCmds"));
	mixin(mixinGUID2string("guidVSDebugCommand"));
	//mixin(mixinGUID2string("VsSetGuidTeamSystemDataCmdIds"));
	//mixin(mixinGUID2string("VsTextTransformationCmdIds"));

	
	mixin(mixinGUID2string("IVsLanguageDebugInfoRemap"));
	mixin(mixinGUID2string("IVsLanguageDebugInfo2"));
	mixin(mixinGUID2string("IVsDebuggableProjectCfg2"));
	mixin(mixinGUID2string("IVsENCRebuildableProjectCfg"));
	mixin(mixinGUID2string("IVsWebServiceProvider"));
	mixin(mixinGUID2string("VisualD_LanguageService"));
		
	return toUTF8(GUID2wstring(guid));
}

string tryformat(...)
{
	string s;
	void putc(dchar c)
	{
		s ~= c;
	}

	try {
		std.format.doFormat(&putc, _arguments, _argptr);
	} 
	catch(Exception e) 
	{
		string msg = e.toString();
		s ~= " EXCEPTION";
	}
	return s;
}

string _tryformat(T)(T* arg)
{
	if(!arg)
		return "null";
	return tryformat("", *arg);
}
	
string varToString(in VARIANT arg) 
{
	if (arg.vt == VT_BSTR)
		return to_string(arg.bstrVal);

	const VARIANT_ALPHABOOL = 0x2;
	int hr;
	VARIANT temp;
	hr = VariantChangeTypeEx(&temp, &arg, GetThreadLocale(), VARIANT_ALPHABOOL, VT_BSTR);
	if (SUCCEEDED(hr))
		return detachBSTR(temp.bstrVal);
	return "invalid";
}

string _toLog(GUID arg) { return GUID2utf8(arg); }
string _toLog(in GUID* arg) { return GUID2utf8(*arg); }
string _toLog(in VARIANT arg) { return format("VAR(%d,%s)", arg.vt, varToString(arg)); }

wstring _toLog(in wchar* arg) { return arg ? to_wstring(arg) : "null"; }
void* _toLog(IUnknown arg) { return cast(void*) arg; }
void* _toLog(in void* arg) { return cast(void*) arg; }

} // !version(test)

int _toLog(int arg) { return arg; }
uint* _toLog(uint* arg) { return arg; }
void* _toLog(Object arg) { return cast(void*) arg; }
//T _toLog(T)(T arg) { return arg; }

uint _toLogOut(uint arg) { return arg; }

void* _toLogOut(IUnknown arg) { return cast(void*) arg; }
string _toLogOut(GUID arg) { return GUID2utf8(arg); }

version(all)
{
	
string _toLogPtr(T)(const(T)* arg)
{
	     static if(is(T : void))     return tryformat("", arg);
	else static if(is(T : IUnknown)) return _tryformat(cast(int**)arg);
	else static if(is(T : GUID))     return arg ? GUID2utf8(*arg) : "null";
	else static if(is(T : LARGE_INTEGER))  return _tryformat(cast(long*)arg);
	else static if(is(T : ULARGE_INTEGER)) return _tryformat(cast(ulong*)arg);
	
	else static if(is(T : IUnknown)) return arg ? _tryformat(cast(int*)*arg) : "null";
	else static if(is(T == struct))  return tryformat("struct ", cast(int*)arg);
	else return _tryformat(arg);
}

} else { // !all
	
string _toLogPtr(T : uint)(T* arg) { return arg ? tryformat("%d", *arg) : "null"; }
string _toLogPtr(T : short)(T* arg) { return arg ? tryformat("%s", arg) : "null"; }
string _toLogPtr(T : wchar*)(T* arg) { return arg ? to_string(*arg) : "null"; }
string _toLogPtr(T : void*)(T* arg) { return arg ? tryformat("", *arg) : "null"; }
string _toLogPtr(T : ulong)(T* arg) { return arg ? tryformat("%d", *arg) : "null"; }

string _toLogPtr(T : IUnknown)(T* arg) { return arg ? tryformat("", cast(int*)*arg) : "null"; }

version(test) {} else {

string _toLogPtr(T : GUID)(T* arg) { return GUID2utf8(*arg); }

string _toLogPtr(T : VARIANT)(T* arg) { return arg ? _toLog(*arg) : "null"; }
string _toLogPtr(T : LARGE_INTEGER)(T* arg) { return arg ? tryformat("%ld", arg.QuadPart) : "null"; }
string _toLogPtr(T : ULARGE_INTEGER)(T* arg) { return arg ? tryformat("%ld", arg.QuadPart) : "null"; }
string _toLogPtr(T : LPCOLESTR)(T arg) { return arg ? tryformat("%s", arg) : "null"; }

string _toLogPtr(T : DISPPARAMS)(T* arg) { return arg ? "struct" : "null"; }
string _toLogPtr(T : EXCEPINFO)(T* arg) { return arg ? "struct" : "null"; }
string _toLogPtr(T : TYPEATTR)(T* arg) { return arg ? "struct" : "null"; }
string _toLogPtr(T : TYPEATTR*)(T* arg) { return arg ? tryformat("", *arg) : "null"; }
string _toLogPtr(T : FUNCDESC*)(T* arg) { return arg ? tryformat("", *arg) : "null"; }
string _toLogPtr(T : VARDESC*)(T* arg) { return arg ? tryformat("", *arg) : "null"; }
string _toLogPtr(T : PVSCOMPONENTSELECTORDATA)(T* arg) { return arg ? tryformat("", *arg) : "null"; }
string _toLogPtr(T : CALPOLESTR*)(T* arg) { return arg ? tryformat("", *arg) : "null"; }

string _toLogPtr(T : FUNCDESC)(T* arg) { return "in"; }
string _toLogPtr(T : VARDESC)(T* arg) { return "in"; }
string _toLogPtr(T : CAUUID)(T* arg) { return "cauuid"; }
string _toLogPtr(T : CALPOLESTR)(T* arg) { return arg ? tryformat("", arg) : "null"; }
string _toLogPtr(T : CADWORD)(T* arg) { return arg ? tryformat("", arg) : "null"; }
string _toLogPtr(T : OLECMD)(T* arg) { return arg ? tryformat("", arg) : "null"; }
string _toLogPtr(T : OLECMDTEXT)(T* arg) { return arg ? tryformat("", arg) : "null"; }
string _toLogPtr(T : RECT)(T* arg) { return arg ? tryformat("", arg) : "null"; }
string _toLogPtr(T : TextSpan)(T* arg) { return arg ? tryformat("", arg) : "null"; }

} // !version(test)

} // !all

int gLogIndent = 0;
__gshared bool gLogFirst = true;

const string gLogFile = "c:/tmp/visuald.log";
const string gLogGCFile = "c:/tmp/visuald.gc";

void logIndent(int n)
{
	gLogIndent += n;
}

FILE* gcLogFh;

extern(C) void log_printf(string fmt, ...)
{
	stdcarg.va_list q;
	stdcarg.va_start!(string)(q, fmt);
	
	char[256] buf;
	int len = vsprintf(buf.ptr, fmt.ptr, q);
	
	if(!gcLogFh)
		gcLogFh = stdcio.fopen(gLogGCFile.ptr, "w");
	
	if(gcLogFh)
		stdcio.fwrite(buf.ptr, len, 1, gcLogFh);
	
	stdcarg.va_end(q);
}

extern(C) void log_flush()
{
	if(gcLogFh)
		stdcio.fflush(gcLogFh);
}

version(test) {

	void logCall(...)
	{
		string s;
		
		void putc(dchar c)
		{
			s ~= c;
		}

		std.format.doFormat(&putc, _arguments, _argptr);
		s ~= "\n";

		std.stdio.fputs(toStringz(s), stdout.getFP);
	}

} else debug {

	class logSync {}

	void logCall(...)
	{
		auto buffer = new char[17 + 1];
		SysTime now = Clock.currTime();
		uint tid = GetCurrentThreadId();
		auto len = sprintf(buffer.ptr, "%02d:%02d:%02d - %04x - ",
		                   now.hour, now.minute, now.second, tid);
		string s = to!string(buffer[0..len]);
		s ~= replicate(" ", gLogIndent);
		
		void putc(dchar c)
		{
			s ~= c;
		}

		try {
			std.format.doFormat(&putc, _arguments, _argptr);
		} 
		catch(Exception e) 
		{
			string msg = e.toString();
			s ~= " EXCEPTION";
		}

		log_string(s);
	}
	
	void log_string(string s)
	{
		s ~= "\n";
		if(gLogFile.length == 0)
			OutputDebugStringA(toStringz(s));
		else
			synchronized(logSync.classinfo)
			{
				static bool canLog;
				if(gLogFirst)
				{
					gLogFirst = false;
					s = "\n" ~ replicate("=", 80) ~ "\n" ~ s;
					
					try
					{
						string bar = "\n" ~ replicate("=", 80) ~ "\n";
						std.file.append(gLogFile, bar);
						canLog = true;
					}
					catch(Exception e)
					{
					}
				}
				if(canLog)
					std.file.append(gLogFile, s);
			}
	}
}
else
{
	void logCall(...)
	{
	}
	void log_string(string s)
	{
	}
}

/////////////////////////////////////////////////////////////////////
// Parsing mangles for fun and profit.
string _getJustName(string mangle)
{
	size_t idx = 1;
	size_t start = idx;
	size_t len = 0;

	while(idx < mangle.length && mangle[idx] >= '0' &&
		mangle[idx] <= '9')
	{
		int size = mangle[idx++] - '0';

		while(mangle[idx] >= '0' && mangle[idx] <= '9')
			size = (size * 10) + (mangle[idx++] - '0');

		start = idx;
		len = size;
		idx += size;
	}

	if(start < mangle.length)
		return mangle[start .. start + len];
	else
		return "";
}

// get anything between first '(' and last ')'
string _getArgs(string func)
{
	int sidx = 0;
	while(sidx < func.length && func[sidx] != '(')
		sidx++;

	int eidx = func.length - 1;
	while(eidx >= 0 && func[eidx] != ')')
		eidx++;

	if(sidx < eidx)
		return func[sidx + 1 .. eidx];
	return "";
}

string _nextArg(string args)
{
	int sidx = 0;
	while(sidx < args.length && args[sidx] != ',')
		sidx++;
	if(sidx < args.length)
		return args[sidx + 1 .. args.length];
	return "";
}

int _find(string s, char c)
{
	for(int i = 0; i < s.length; i++)
		if(s[i] == c)
			return i;
	return -1;
}

string _getIdentifier(string args)
{
	string ident;
	int sidx = -1;
	for(int idx = 0; ; idx++)
	{
		dchar ch = (idx < args.length ? args[idx] : ',');
		if(sidx >= 0)
		{
			if(!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
			     (ch >= '0' && ch <= '9') || ch == '_'))
			{
			     ident = args[sidx .. idx];
			     sidx = -1;
			}
		}
		else if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_')
			sidx = idx;

		if(ch == ',')
			break;
	}
	return ident;
}

string _toArgIdx(int idx)
{
	string s = "";
	if(idx == 0)
		s = "0";
	else
		while(idx > 0)
		{
			s = cast(char)('0' + (idx % 10)) ~ s;
			idx = idx / 10;
		}

	return s;
}

// useargs: 0 - identifier, 1 - C-style, 2 - D-style
string _getLogCall(string func, string type, bool addthis, int useargs)
{
	string call = "logCall(\"";
	string args = _getArgs(type);
	string idlist;

	if(addthis)
	{
		call ~= "%s.";
		idlist ~= ", this";
	}
	call ~= func ~ "(";

	int arg = 0;
	if(addthis)
	{
		call ~= "this=%s";
		idlist ~= ", cast(void*)this";
		arg = 1;
	}
	while(args.length > 0)
	{
		bool isOut = (args.length > 4 && args[0 .. 4] == "out ");
		string ident = _getIdentifier(args);
		if(ident.length > 0)
		{
			if(arg > 0)
				call ~= ", ";
			if(useargs == 0)
			{
				call ~= (isOut ? "out " : "") ~ ident ~ "=%" ~ 's'; // cast(char)(arg + '1');
				idlist ~= ", _toLog(" ~ (isOut ? "&" : "") ~ ident ~ ")";
			}
			else
			{
				call ~= "%" ~ 's'; // cast(char)(arg + '1');
				string sidx = _toArgIdx(addthis ? arg - 1 : arg);
				idlist ~= ", _toLog(*cast(_argtypes[" ~ sidx ~ "]*)(_ebp+_argoff(" ~ _toArgIdx(arg) ~ ")))";
			}
			arg++;
		}
		args = _nextArg(args);
	}
	call ~= ")\"" ~ idlist ~ ");\n";
	return call;
}

string _getLogReturn(string func, string type)
{
	string call = "logCall(\"" ~ func ~ " returns ";
	string args = _getArgs(type);
	string idlist;

	int arg = 0;
	while(args.length > 0)
	{
		string prevargs = args;
		bool isOut = (args.length > 4 && args[0 .. 4] == "out ");
		string ident = _getIdentifier(args);
		args = _nextArg(args);
		bool isPtr = false;
		if(!isOut)
		{
			int len = prevargs.length;
			if((len < 5  || prevargs[0..5] != "void*") &&
			   (len < 4  || prevargs[0..4] != "MSG*") &&
			   (len < 13 || prevargs[0..13] != "PROPPAGEINFO*"))
			{
				int idx = _find(prevargs, '*');
				isPtr = (idx >= 0 && idx < prevargs.length - args.length);
			}
		}

		if(ident.length > 0 && (isOut || isPtr))
		{
			if(arg > 0)
				call ~= ", ";
			call ~= ident ~ "=%s";
			if(isOut)
				idlist ~= ", _toLogOut(" ~ ident ~ ")";
			else
				idlist ~= ", _toLogPtr(" ~ ident ~ ")";
			arg++;
		}
	}
	if(arg == 0)
		return "";
	call ~= "\"" ~ idlist ~ ");\n";

	return call;
}

const string nl = " "; // "\n";
const string FuncNameMix = "struct __FUNCTION {} static const string __FUNCTION__ = _getJustName(__FUNCTION.mangleof);" ~ nl;
const string _hasThisMix = "static const bool hasThis = true;" ~ nl;

const string _LogCallMix = "static const string __LOGCALL__ = _getLogCall(__FUNCTION__, typeof(&mixin(__FUNCTION__)).stringof, hasThis, 0);" ~ nl;
const string _LogReturnMix = "static const string __LOGRETURN__ = _getLogReturn(__FUNCTION__, typeof(&mixin(__FUNCTION__)).stringof);" ~ nl;

const string _getEBP = "byte* _ebp; asm { mov _ebp,EBP; } _ebp = _ebp + 8;" ~ nl;
const string _LogCallArgType = "static const string __ARGTYPES__ = \"alias ParameterTypeTuple!(\" ~ __FUNCTION__ ~ \") _argtypes;\";" ~ nl;
const string _LogCallArgOff  = "static int _argoff(int n) { int off = 0; foreach(i, T; _argtypes) if(i < n) off += T.sizeof; return off; }" ~ nl;
const string _LogCallMix2 = "static const string __LOGCALL__ = _getLogCall(__FUNCTION__, typeof(&mixin(__FUNCTION__)).stringof, hasThis, 1);" ~ nl;

const string _LogIndent = "logIndent(1); scope(exit) { " ~ "mixin(__LOGRETURN__);" ~ "logIndent(-1); }" ~ nl;
const string _LogIndentNoRet = "logIndent(1); scope(exit) logIndent(-1);" ~ nl;

debug {
const string LogCallMix = FuncNameMix ~ _hasThisMix ~ _LogCallMix ~ _LogReturnMix ~ "mixin(__LOGCALL__);" ~ _LogIndent;
const string LogCallMix2 = FuncNameMix ~ _hasThisMix ~ _getEBP ~ _LogCallArgType ~ "mixin(__ARGTYPES__);" ~ _LogCallArgOff ~ _LogCallMix2 ~ "mixin(__LOGCALL__);" ~ _LogIndentNoRet;
const string LogCallMixNoRet = FuncNameMix ~ _hasThisMix ~ _LogCallMix ~ "mixin(__LOGCALL__);" ~ _LogIndentNoRet;
} else {
const string LogCallMix = "";
const string LogCallMix2 = "";
const string LogCallMixNoRet = "";
}

/+
void test(int a0, Object o)
{
    mixin(FuncNameMix);
    pragma(msg, __FUNCTION__); // shows "test"    
    pragma(msg,typeof(&mixin(__FUNCTION__)).stringof); // shows "void function(int a0, Object o)"
    pragma(msg,_getLogCall(__FUNCTION__, typeof(&mixin(__FUNCTION__)).stringof, false)); // shows "void function(int a0, Object o)"
}
+/

/+
template tLogCall(alias s)
{
	struct __STRUCT {};
	static const string __FUNCTION__ = _getJustName(__STRUCT.mangleof);

	//pragma(msg, s.mangleof); // shows "test"    
	pragma(msg, __STRUCT.mangleof); // shows "test"    
	pragma(msg, __FUNCTION__); // shows "test"    
	alias ParameterTypeTuple!(test2) types;

	void* pthis = cast(void*)this;

}

class t
{
	void test2(int a0, Object o, uint x)
	{
		struct __STR {}
		mixin tLogCall!(__STR);
	}
}
+/

version(test) {

import std.stdio;
import std.string;

template log_arg(T)
{
    T log_arg(inout void* _argptr)
    {
	T arg = *cast(T*)_argptr;
	_argptr = _argptr + ((T.sizeof + int.sizeof - 1) & ~(int.sizeof - 1));
	return arg;
    }
}

class t
{
	void test2(int a0, Object o, uint x)
	{
		mixin(LogCallMix);

		alias ParameterTypeTuple!(test2) types;
		pragma(msg,types.stringof);
		TypeInfo[] ti;
		foreach_reverse(t; types)
		{
			pragma(msg,t.stringof);
			ti ~= typeid(t);
		}

		void* pthis = cast(void*)this;
		void* p; asm { mov p,EBP; } p = p + 8;

		std.format.doFormat(&putc, ti, p);
		logCall("doFormat = %s", s);

		auto arg3 = log_arg!(types[2])(p);
		auto arg2 = log_arg!(types[1])(p);
		auto arg1 = log_arg!(types[0])(p);

		logCall("%s.test2(this=%s,a0=%s,o=%s,x=%s)", this, pthis, _toLog(arg1), _toLog(arg2), _toLog(arg3));

		int *vp = cast(int*) &this;
		for(int i = -6; i < 6; i++)
			logCall("%d: %x", i, vp[i]);
	}
}

int rc = 2;

int main(char[][] argv)
{
	t at = new t;
	at.test2(3, null, 7);
	return rc;
}

}
