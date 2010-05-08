// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module config;

import std.string;
import std.conv;
import std.path;
import std.utf;

import xml = xmlwrap;

import sdk.vsi.vsshell;

import comutil;
import logutil;
import hierutil;
import hierarchy;
import chiernode;
import dproject;
import dpackage;
import build;
import propertypage;
import stringutil;
import fileutil;

extern(Windows) HRESULT CoDisconnectObject(IUnknown pUnk, DWORD dwReserved);

const string kToolResourceCompiler = "Resource Compiler";
const string kCmdLogFileExtension = "build";

///////////////////////////////////////////////////////////////

T clone(T)(T object)
{
	auto size = object.classinfo.init.length;
	object = cast(T) ((cast(void*)object) [0..size].dup.ptr );
//	object.__monitor = null;
	return object;
}

///////////////////////////////////////////////////////////////

version(D_Version2)
{
	ubyte  toUbyte(string s) { return to!(ubyte)(s); }
	float  toFloat(string s) { return to!(float)(s); }
	string uintToString(uint x) { return to!(string)(x); }
}
else
{
	string uintToString(uint x) { return toString(x); }
}

string toElem(bool b) { return b ? "1" : "0"; }
string toElem(float f) { return to!(string)(f); }
string toElem(string s) { return s; }
string toElem(uint x) { return uintToString(x); }

void _fromElem(xml.Element e, ref string x) { x = e.text(); }
void _fromElem(xml.Element e, ref bool x)   { x = e.text() == "1"; }
void _fromElem(xml.Element e, ref ubyte x)  { x = toUbyte(e.text()); }
void _fromElem(xml.Element e, ref uint x)   { x = toUbyte(e.text()); }
void _fromElem(xml.Element e, ref float x)  { x = toFloat(e.text()); }

void fromElem(T)(xml.Element e, string s, ref T x)
{
	if(xml.Element el = xml.getElement(e, s))
		_fromElem(el, x);
}

class ProjectOptions
{
	bool obj;		// write object file
	bool link;		// perform link
	bool lib;		// write library file instead of object file(s)
	bool multiobj;		// break one object file into multiple ones
	bool oneobj;		// write one object file instead of multiple ones
	bool trace;		// insert profiling hooks
	bool quiet;		// suppress non-error messages
	bool verbose;		// verbose compile
	bool vtls;		// identify thread local variables
	ubyte symdebug;		// insert debug symbolic information
	bool optimize;		// run optimizer
	ubyte cpu;		// target CPU
	bool isX86_64;		// generate X86_64 bit code
	bool isLinux;		// generate code for linux
	bool isOSX;		// generate code for Mac OSX
	bool isWindows;		// generate code for Windows
	bool isFreeBSD;		// generate code for FreeBSD
	bool isSolaris;		// generate code for Solaris
	bool scheduler;		// which scheduler to use
	bool useDeprecated;	// allow use of deprecated features
	bool useAssert;		// generate runtime code for assert()'s
	bool useInvariants;	// generate class invariant checks
	bool useIn;		// generate precondition checks
	bool useOut;		// generate postcondition checks
	ubyte useArrayBounds;	// 0: no array bounds checks
	// 1: array bounds checks for safe functions only
	// 2: array bounds checks for all functions
	bool noboundscheck;	// no array bounds checking at all
	bool useSwitchError;	// check for switches without a default
	bool useUnitTests;	// generate unittest code
	bool useInline;		// inline expand functions
	bool release;		// build release version
	bool preservePaths;	// !=0 means don't strip path from source file
	bool warnings;		// enable warnings
	bool pic;		// generate position-independent-code for shared libs
	bool cov;		// generate code coverage data
	bool nofloat;		// code should not pull in floating point support
	bool ignoreUnsupportedPragmas;	// rather than error on them
	float Dversion;		// D version number

	bool otherDMD;		// use non-default DMD
	string program;		// program name
	string imppath;		// array of char*'s of where to look for import modules
	string fileImppath;	// array of char*'s of where to look for file import modules
	string outdir;		// target output directory
	string objdir;		// .obj/.lib file output directory
	string objname;		// .obj file output name
	string libname;		// .lib file output name

	bool doDocComments;	// process embedded documentation comments
	string docdir;		// write documentation file to docdir directory
	string docname;		// write documentation file to docname
	string ddocfiles;	// macro include files for Ddoc

	bool doHdrGeneration;	// process embedded documentation comments
	string hdrdir;		// write 'header' file to docdir directory
	string hdrname;		// write 'header' file to docname

	bool doXGeneration;	// write JSON file
	string xfilename;	// write JSON file to xfilename

	uint debuglevel;	// debug level
	string debugids;	// debug identifiers

	uint versionlevel;	// version level
	string versionids;	// version identifiers

	bool dump_source;
	uint mapverbosity;
	bool createImplib;

	string defaultlibname;	// default library for non-debug builds
	string debuglibname;	// default library for debug builds

	string moduleDepsFile;	// filename for deps output

	bool run;		// run resulting executable
	string runargs;		// arguments for executable

	bool runCv2pdb;		// run cv2pdb on executable
	string pathCv2pdb;	// exe path for cv2pdb 

	// Linker stuff
	string objfiles;
	string linkswitches;
	string libfiles;
	string deffile;
	string resfile;
	string exefile;

	string additionalOptions;
	string preBuildCommand;
	string postBuildCommand;

	// debug options
	string debugtarget;
	string debugarguments;
	string debugworkingdir;
	bool debugattach;
	string debugremote;

	string filesToClean;
	
	this(bool dbg)
	{
		Dversion = 2;
		exefile = "$(OutDir)\\$(ProjectName).exe";
		outdir = "$(ConfigurationName)";
		objdir = "$(OutDir)";
		debugtarget = "$(TARGETPATH)";
		pathCv2pdb = "$(VisualDInstallDir)cv2pdb\\cv2pdb.exe";
		program = "$(DMDInstallDir)windows\\bin\\dmd.exe";
		xfilename = "$(IntDir)\\$(ProjectName).json";
		
		filesToClean = "*.obj";
		
		runCv2pdb = dbg;
		symdebug = dbg ? 1 : 0;
		release = dbg ? 0 : 1;
	}

	string buildCommandLine()
	{
		string cmd;
		if(otherDMD && program.length)
			cmd = quoteNormalizeFilename(program);
		else
			cmd = "dmd";

		if(lib)
			cmd ~= " -lib";
		if(multiobj)
			cmd ~= " -multiobj";
		if(trace)
			cmd ~= " -trace";
		if(quiet)
			cmd ~= " -quiet";
		if(verbose)
			cmd ~= " -v";
		if(Dversion >= 2 && vtls)
			cmd ~= " -vtls";
		if(symdebug == 1)
			cmd ~= " -g";
		if(symdebug == 2)
			cmd ~= " -gc";
		if(optimize)
			cmd ~= " -O";
		if(useDeprecated)
			cmd ~= " -d";
		if(Dversion >= 2 && noboundscheck)
			cmd ~= " -noboundscheck";
		if(useUnitTests)
			cmd ~= " -unittest";
		if(useInline)
			cmd ~= " -inline";
		if(release)
			cmd ~= " -release";
		else
			cmd ~= " -debug";
		if(preservePaths)
			cmd ~= " -op";
		if(warnings)
			cmd ~= " -w";
		if(cov)
			cmd ~= " -cov";
		if(nofloat)
			cmd ~= " -nofloat";
		if(ignoreUnsupportedPragmas)
			cmd ~= " -ignore";

		if(doDocComments)
		{
			cmd ~= " -D";
			if(docdir.length)
				cmd ~= " -Dd" ~ quoteNormalizeFilename(docdir);
			if(docname.length)
				cmd ~= " -Df" ~ quoteNormalizeFilename(docname);
		}

		if(doHdrGeneration)
		{
			cmd ~= " -H";
			if(hdrdir.length)
				cmd ~= " -Hd" ~ quoteNormalizeFilename(hdrdir);
			if(hdrname.length)
				cmd ~= " -Hf" ~ quoteNormalizeFilename(hdrname);
		}

		if(doXGeneration)
		{
			cmd ~= " -X";
			if(xfilename.length)
				cmd ~= " -Xf" ~ quoteNormalizeFilename(xfilename);
		}

		string[] imports = split(imppath, ";");
		foreach(imp; imports)
			if(strip(imp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(imp));

		string[] fileImports = split(fileImppath, ";");
		foreach(imp; fileImports)
			if(strip(imp).length)
				cmd ~= " -J" ~ quoteNormalizeFilename(strip(imp));

		string[] versions = split(versionids, ";");
		foreach(ver; versions)
			if(strip(ver).length)
				cmd ~= " -version=" ~ strip(ver);

		string[] ids = split(debugids, ";");
		foreach(id; ids)
			if(strip(id).length)
				cmd ~= " -debug=" ~ strip(id);

		string dmdoutfile = getTargetPath();
		if(symdebug && runCv2pdb && !lib)
			dmdoutfile ~= "_cv";

		cmd ~= " -of" ~ quoteNormalizeFilename(dmdoutfile);
		cmd ~= " -deps=" ~ quoteNormalizeFilename(getDependenciesPath());
		cmd ~= " -map \"$(INTDIR)\\$(SAFEPROJECTNAME).map\"";
		switch(mapverbosity)
		{
		case 0: cmd ~= " -L/NOMAP"; break; // actually still creates map file
		case 1: cmd ~= " -L/MAP:ADDRESS"; break;
		case 2: break;
		case 3: cmd ~= " -L/MAP:FULL"; break;
		case 4: cmd ~= " -L/MAP:FULL -L/XREF"; break;
		default: break;
		}

		if(!lib)
		{
			if(createImplib)
				cmd ~= " -L/IMPLIB:$(OUTDIR)\\$(PROJECTNAME).lib";
			if(objfiles.length)
				cmd ~= " " ~ objfiles;
			if(deffile.length)
				cmd ~= " " ~ deffile;
			if(libfiles.length)
				cmd ~= " " ~ libfiles;
			if(resfile.length)
				cmd ~= " " ~ resfile;
		}
		return cmd;
	}

	string getTargetPath()
	{
		if(exefile.length)
			return normalizePath(exefile);
		if(lib)
			return "$(OutDir)\\$(ProjectName).lib";
		return "$(OutDir)\\$(ProjectName).exe";
	}

	string getDependenciesPath()
	{
		return normalizeDir(objdir) ~ "$(ProjectName).dep";
	}

	string getCommandLinePath()
	{
		return normalizeDir(objdir) ~ "$(ProjectName)." ~ kCmdLogFileExtension;
	}

	string appendCv2pdb()
	{
		if(symdebug && runCv2pdb && !lib)
		{
			string target = getTargetPath();
			string cmd = quoteFilename(pathCv2pdb) ~ " -D" ~ to!(string)(Dversion) ~ " ";
			cmd ~= quoteFilename(target ~ "_cv") ~ " " ~ quoteFilename(target);
			return cmd;
		}
		return "";
	}

	string replaceEnvironment(string cmd, Config config, string inputfile = "")
	{
		if(indexOf(cmd, '$') < 0)
			return cmd;
		
		string configname = config.mName;
		string projectpath = config.GetProjectPath();
		string safeprojectpath = projectpath.replace(" ", "_");

		string[string] replacements;
		IVsSolution srpSolution = queryService!(IVsSolution);
		if(srpSolution)
		{
			BSTR pbstrSolutionFile;
			if(srpSolution.GetSolutionInfo(null, &pbstrSolutionFile, null) == S_OK)
			{
				string solutionpath = detachBSTR(pbstrSolutionFile);
				addFileMacros(solutionpath, "SOLUTION", replacements);
			}
			srpSolution.Release();
		}
		replacements["PLATFORMNAME"] = "Win32";
		addFileMacros(projectpath, "PROJECT", replacements);
		addFileMacros(safeprojectpath, "SAFEPROJECT", replacements);
		addFileMacros(inputfile.length ? inputfile : projectpath, "INPUT", replacements);
		replacements["CONFIGURATIONNAME"] = configname;
		replacements["OUTDIR"] = outdir;
		replacements["INTDIR"] = objdir;
		replacements["TARGETPATH"] = getTargetPath();
		Package.GetGlobalOptions().addReplacements(replacements);

		string target = replaceMacros(getTargetPath(), replacements);
		addFileMacros(target, "TARGET", replacements);

		return replaceMacros(cmd, replacements);
	}

	void writeXML(xml.Element elem)
	{
		elem ~= new xml.Element("obj", toElem(obj));
		elem ~= new xml.Element("link", toElem(link));
		elem ~= new xml.Element("lib", toElem(lib));
		elem ~= new xml.Element("multiobj", toElem(multiobj));
		elem ~= new xml.Element("oneobj", toElem(oneobj));
		elem ~= new xml.Element("trace", toElem(trace));
		elem ~= new xml.Element("quiet", toElem(quiet));
		elem ~= new xml.Element("verbose", toElem(verbose));
		elem ~= new xml.Element("vtls", toElem(vtls));
		elem ~= new xml.Element("symdebug", toElem(symdebug));
		elem ~= new xml.Element("optimize", toElem(optimize));
		elem ~= new xml.Element("cpu", toElem(cpu));
		elem ~= new xml.Element("isX86_64", toElem(isX86_64));
		elem ~= new xml.Element("isLinux", toElem(isLinux));
		elem ~= new xml.Element("isOSX", toElem(isOSX));
		elem ~= new xml.Element("isWindows", toElem(isWindows));
		elem ~= new xml.Element("isFreeBSD", toElem(isFreeBSD));
		elem ~= new xml.Element("isSolaris", toElem(isSolaris));
		elem ~= new xml.Element("scheduler", toElem(scheduler));
		elem ~= new xml.Element("useDeprecated", toElem(useDeprecated));
		elem ~= new xml.Element("useAssert", toElem(useAssert));
		elem ~= new xml.Element("useInvariants", toElem(useInvariants));
		elem ~= new xml.Element("useIn", toElem(useIn));
		elem ~= new xml.Element("useOut", toElem(useOut));
		elem ~= new xml.Element("useArrayBounds", toElem(useArrayBounds));
		elem ~= new xml.Element("noboundscheck", toElem(noboundscheck));
		elem ~= new xml.Element("useSwitchError", toElem(useSwitchError));
		elem ~= new xml.Element("useUnitTests", toElem(useUnitTests));
		elem ~= new xml.Element("useInline", toElem(useInline));
		elem ~= new xml.Element("release", toElem(release));
		elem ~= new xml.Element("preservePaths", toElem(preservePaths));
		elem ~= new xml.Element("warnings", toElem(warnings));
		elem ~= new xml.Element("pic", toElem(pic));
		elem ~= new xml.Element("cov", toElem(cov));
		elem ~= new xml.Element("nofloat", toElem(nofloat));
		elem ~= new xml.Element("Dversion", toElem(Dversion));
		elem ~= new xml.Element("ignoreUnsupportedPragmas", toElem(ignoreUnsupportedPragmas));

		elem ~= new xml.Element("otherDMD", toElem(otherDMD));
		elem ~= new xml.Element("program", toElem(program));
		elem ~= new xml.Element("imppath", toElem(imppath));
		elem ~= new xml.Element("fileImppath", toElem(fileImppath));
		elem ~= new xml.Element("outdir", toElem(outdir));
		elem ~= new xml.Element("objdir", toElem(objdir));
		elem ~= new xml.Element("objname", toElem(objname));
		elem ~= new xml.Element("libname", toElem(libname));

		elem ~= new xml.Element("doDocComments", toElem(doDocComments));
		elem ~= new xml.Element("docdir", toElem(docdir));
		elem ~= new xml.Element("docname", toElem(docname));
		elem ~= new xml.Element("ddocfiles", toElem(ddocfiles));

		elem ~= new xml.Element("doHdrGeneration", toElem(doHdrGeneration));
		elem ~= new xml.Element("hdrdir", toElem(hdrdir));
		elem ~= new xml.Element("hdrname", toElem(hdrname));

		elem ~= new xml.Element("doXGeneration", toElem(doXGeneration));
		elem ~= new xml.Element("xfilename", toElem(xfilename));

		elem ~= new xml.Element("debuglevel", toElem(debuglevel));
		elem ~= new xml.Element("debugids", toElem(debugids));

		elem ~= new xml.Element("versionlevel", toElem(versionlevel));
		elem ~= new xml.Element("versionids", toElem(versionids));

		elem ~= new xml.Element("dump_source", toElem(dump_source));
		elem ~= new xml.Element("mapverbosity", toElem(mapverbosity));
		elem ~= new xml.Element("createImplib", toElem(createImplib));

		elem ~= new xml.Element("defaultlibname", toElem(defaultlibname));
		elem ~= new xml.Element("debuglibname", toElem(debuglibname));

		elem ~= new xml.Element("moduleDepsFile", toElem(moduleDepsFile));

		elem ~= new xml.Element("run", toElem(run));
		elem ~= new xml.Element("runargs", toElem(runargs));

		elem ~= new xml.Element("runCv2pdb", toElem(runCv2pdb));
		elem ~= new xml.Element("pathCv2pdb", toElem(pathCv2pdb));
		
		// Linker stuff
		elem ~= new xml.Element("objfiles", toElem(objfiles));
		elem ~= new xml.Element("linkswitches", toElem(linkswitches));
		elem ~= new xml.Element("libfiles", toElem(libfiles));
		elem ~= new xml.Element("deffile", toElem(deffile));
		elem ~= new xml.Element("resfile", toElem(resfile));
		elem ~= new xml.Element("exefile", toElem(exefile));

		elem ~= new xml.Element("additionalOptions", toElem(additionalOptions));
		elem ~= new xml.Element("preBuildCommand", toElem(preBuildCommand));
		elem ~= new xml.Element("postBuildCommand", toElem(postBuildCommand));
	
		elem ~= new xml.Element("debugtarget", toElem(debugtarget));
		elem ~= new xml.Element("debugarguments", toElem(debugarguments));
		elem ~= new xml.Element("debugworkingdir", toElem(debugworkingdir));
		elem ~= new xml.Element("debugattach", toElem(debugattach));
		elem ~= new xml.Element("debugremote", toElem(debugremote));
		
		elem ~= new xml.Element("filesToClean", toElem(filesToClean));
		
	}

	void readXML(xml.Element elem)
	{
		fromElem(elem, "obj", obj);
		fromElem(elem, "link", link);
		fromElem(elem, "lib", lib);
		fromElem(elem, "multiobj", multiobj);
		fromElem(elem, "oneobj", oneobj);
		fromElem(elem, "trace", trace);
		fromElem(elem, "quiet", quiet);
		fromElem(elem, "verbose", verbose);
		fromElem(elem, "vtls", vtls);
		fromElem(elem, "symdebug", symdebug);
		fromElem(elem, "optimize", optimize);
		fromElem(elem, "cpu", cpu);
		fromElem(elem, "isX86_64", isX86_64);
		fromElem(elem, "isLinux", isLinux);
		fromElem(elem, "isOSX", isOSX);
		fromElem(elem, "isWindows", isWindows);
		fromElem(elem, "isFreeBSD", isFreeBSD);
		fromElem(elem, "isSolaris", isSolaris);
		fromElem(elem, "scheduler", scheduler);
		fromElem(elem, "useDeprecated", useDeprecated);
		fromElem(elem, "useAssert", useAssert);
		fromElem(elem, "useInvariants", useInvariants);
		fromElem(elem, "useIn", useIn);
		fromElem(elem, "useOut", useOut);
		fromElem(elem, "useArrayBounds", useArrayBounds);
		fromElem(elem, "noboundscheck", noboundscheck);
		fromElem(elem, "useSwitchError", useSwitchError);
		fromElem(elem, "useUnitTests", useUnitTests);
		fromElem(elem, "useInline", useInline);
		fromElem(elem, "release", release);
		fromElem(elem, "preservePaths", preservePaths);
		fromElem(elem, "warnings", warnings);
		fromElem(elem, "pic", pic);
		fromElem(elem, "cov", cov);
		fromElem(elem, "nofloat", nofloat);
		fromElem(elem, "Dversion", Dversion);
		fromElem(elem, "ignoreUnsupportedPragmas", ignoreUnsupportedPragmas );

		fromElem(elem, "otherDMD", otherDMD);
		fromElem(elem, "program", program);
		fromElem(elem, "imppath", imppath);
		fromElem(elem, "fileImppath", fileImppath);
		fromElem(elem, "outdir", outdir);
		fromElem(elem, "objdir", objdir);
		fromElem(elem, "objname", objname);
		fromElem(elem, "libname", libname);

		fromElem(elem, "doDocComments", doDocComments);
		fromElem(elem, "docdir", docdir);
		fromElem(elem, "docname", docname);
		fromElem(elem, "ddocfiles", ddocfiles);

		fromElem(elem, "doHdrGeneration", doHdrGeneration);
		fromElem(elem, "hdrdir", hdrdir);
		fromElem(elem, "hdrname", hdrname);

		fromElem(elem, "doXGeneration", doXGeneration);
		fromElem(elem, "xfilename", xfilename);

		fromElem(elem, "debuglevel", debuglevel);
		fromElem(elem, "debugids", debugids);

		fromElem(elem, "versionlevel", versionlevel);
		fromElem(elem, "versionids", versionids);

		fromElem(elem, "dump_source", dump_source);
		fromElem(elem, "mapverbosity", mapverbosity);
		fromElem(elem, "createImplib", createImplib);

		fromElem(elem, "defaultlibname", defaultlibname);
		fromElem(elem, "debuglibname", debuglibname);

		fromElem(elem, "moduleDepsFile", moduleDepsFile);

		fromElem(elem, "run", run);
		fromElem(elem, "runargs", runargs);

		fromElem(elem, "runCv2pdb", runCv2pdb);
		fromElem(elem, "pathCv2pdb", pathCv2pdb);

		// Linker stuff
		fromElem(elem, "objfiles", objfiles);
		fromElem(elem, "linkswitches", linkswitches);
		fromElem(elem, "libfiles", libfiles);
		fromElem(elem, "deffile", deffile);
		fromElem(elem, "resfile", resfile);
		fromElem(elem, "exefile", exefile);
	
		fromElem(elem, "additionalOptions", additionalOptions);
		fromElem(elem, "preBuildCommand", preBuildCommand);
		fromElem(elem, "postBuildCommand", postBuildCommand);

		fromElem(elem, "debugtarget", debugtarget);
		fromElem(elem, "debugarguments", debugarguments);
		fromElem(elem, "debugworkingdir", debugworkingdir);
		fromElem(elem, "debugattach", debugattach);
		fromElem(elem, "debugremote", debugremote);

		fromElem(elem, "filesToClean", filesToClean);
	}
};

class ConfigProvider : DisposingComObject,
	// IVsExtensibleObject,
	IVsCfgProvider2, 
	IVsProjectCfgProvider
{
	this(Project prj)
	{
		mProject = prj;
//		mConfigs ~= addref(new Config(this, "Debug"));
//		mConfigs ~= addref(new Config(this, "Release"));
	}

	Config addConfig(string name)
	{
		Config cfg = new Config(this, name);
		mConfigs ~= addref(cfg);
		return cfg;
	}

	void addConfigsToXml(xml.Document doc)
	{
		foreach(Config cfg; mConfigs)
		{
			auto config = new xml.Element("Config");
			xml.setAttribute(config, "name", cfg.mName);

			ProjectOptions opt = cfg.GetProjectOptions();
			opt.writeXML(config);
			doc ~= config;
		}
	}

	void Dispose()
	{
		foreach(Config cfg; mConfigs)
			release(cfg);
		mConfigs = mConfigs.init;
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(IVsCfgProvider) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCfgProvider2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectCfgProvider) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsCfgProvider
	override int GetCfgs( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ IVsCfg *rgpcfg,
		/* [optional][out] */ ULONG *pcActual,
		/* [optional][out] */ VSCFGFLAGS *prgfFlags)
	{
		mixin(LogCallMix);

		for(int i = 0; i < celt && i < mConfigs.length; i++)
			rgpcfg[i] = addref(mConfigs[i]);
		if(pcActual)
			*pcActual = mConfigs.length;
		if(prgfFlags)
			*prgfFlags = cast(VSCFGFLAGS) 0;
		return S_OK;
	}

	// IVsProjectCfgProvider
	override int OpenProjectCfg( 
		/* [in] */ in wchar* szProjectCfgCanonicalName,
		/* [out] */ IVsProjectCfg *ppIVsProjectCfg)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_UsesIndependentConfigurations( 
		/* [out] */ BOOL *pfUsesIndependentConfigurations)
	{
		logCall("%s.get_UsesIndependentConfigurations(pfUsesIndependentConfigurations=%s)", this, _toLog(pfUsesIndependentConfigurations));
		return returnError(E_NOTIMPL);
	}

	// IVsCfgProvider2
	override int GetCfgNames( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		for(int i = 0; i < celt && i < mConfigs.length; i++)
			rgbstr[i] = allocBSTR(mConfigs[i].mName);
		if(pcActual)
			*pcActual = mConfigs.length;
		return S_OK;
	}


	override int GetPlatformNames( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		if(celt >= 1 && rgbstr)
			*rgbstr = allocBSTR(kPlatform);
		if(pcActual)
			*pcActual = 1;
		return S_OK;
	}

	override int GetCfgOfName( 
		/* [in] */ in wchar* pszCfgName,
		/* [in] */ in wchar* pszPlatformName,
		/* [out] */ IVsCfg *ppCfg)
	{
		mixin(LogCallMix);
		string cfg = to_string(pszCfgName);
		string plat = to_string(pszPlatformName);
		
		if(plat == "" || plat == kPlatform)
			for(int i = 0; mConfigs.length; i++)
				if(mConfigs[i].mName == cfg)
				{
					*ppCfg = addref(mConfigs[i]);
					return S_OK;
				}

		return returnError(E_INVALIDARG);
	}

	extern(D) void NotifyConfigEvent(void delegate(IVsCfgProviderEvents) dg)
	{
		// make a copy of the callback list, because it might change during execution of the callback
		IVsCfgProviderEvents[] cbs;

		foreach(cb; mCfgProviderEvents)
			cbs ~= cb;

		foreach(cb; cbs)
			dg(cb);
	}

	override int AddCfgsOfCfgName( 
		/* [in] */ in wchar* pszCfgName,
		/* [in] */ in wchar* pszCloneCfgName,
		/* [in] */ in BOOL fPrivate)
	{
		mixin(LogCallMix);

		string strCfgName = to_string(pszCfgName);
		string strCloneCfgName = to_string(pszCloneCfgName);

		// Check if the CfgName already exists and that CloneCfgName exists
		Config clonecfg;
		foreach(c; mConfigs)
			if(c.mName == strCfgName)
				return returnError(E_FAIL);
			else if(c.mName == strCloneCfgName)
				clonecfg = c;
		
		if(strCloneCfgName.length && !clonecfg)
			return returnError(E_FAIL);

		//if(!mProject.QueryEditProjectFile())
		//	return returnError(E_ABORT);
    
		Config config = new Config(this, strCfgName);
		if (clonecfg)
			config.mProjectOptions = clone(clonecfg.mProjectOptions);

		mConfigs ~= addref(config);

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameAdded(pszCfgName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int DeleteCfgsOfCfgName( 
		/* [in] */ in wchar* pszCfgName)
	{
		logCall("%s.DeleteCfgsOfCfgName(pszCfgName=%s)", this, _toLog(pszCfgName));

		string strCfgName = to_string(pszCfgName);
		int index = -1;
		foreach(i, c; mConfigs)
			if(c.mName == strCfgName)
				index = i;
		if(index < 0)
			return returnError(E_FAIL);

		mConfigs = mConfigs[0..index] ~ mConfigs[index+1..$];

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameDeleted(pszCfgName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int RenameCfgsOfCfgName( 
		/* [in] */ in wchar* pszOldName,
		/* [in] */ in wchar* pszNewName)
	{
		mixin(LogCallMix);

		string strOldName = to_string(pszOldName);
		string strNewName = to_string(pszNewName);

		Config config;
		foreach(c; mConfigs)
			if(c.mName == strNewName)
				return returnError(E_FAIL);
			else if(c.mName == strOldName)
				config = c;

		if(!config)
			return returnError(E_FAIL);

		//if(!mProject.QueryEditProjectFile())
		//	return returnError(E_ABORT);

		config.mName = strNewName;

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameRenamed(pszOldName, pszNewName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int AddCfgsOfPlatformName( 
		/* [in] */ in wchar* pszPlatformName,
		/* [in] */ in wchar* pszClonePlatformName)
	{
		logCall("%s.AddCfgsOfPlatformName(pszPlatformName=%s,pszClonePlatformName=%s)", this, _toLog(pszPlatformName), _toLog(pszClonePlatformName));
		return returnError(E_NOTIMPL);
	}

	override int DeleteCfgsOfPlatformName( 
		/* [in] */ in wchar* pszPlatformName)
	{
		logCall("%s.DeleteCfgsOfPlatformName(pszPlatformName=%s)", this, _toLog(pszPlatformName));
		return returnError(E_NOTIMPL);
	}

	override int GetSupportedPlatformNames( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		if(celt >= 1)
			*rgbstr = allocBSTR(kPlatform);
		if(pcActual)
			*pcActual = 1;
		return S_OK;
	}

	override int GetCfgProviderProperty( 
		/* [in] */ in VSCFGPROPID propid,
		/* [out] */ VARIANT *var)
	{
		mixin(LogCallMix);

		switch(propid)
		{
		case VSCFGPROPID_SupportsCfgAdd:
		case VSCFGPROPID_SupportsCfgDelete:
		case VSCFGPROPID_SupportsCfgRename:
			var.vt = VT_BOOL;
			var.boolVal = true;
			return S_OK;
		default:
			break;
		}
		return returnError(E_NOTIMPL);
	}

	override int AdviseCfgProviderEvents( 
		/* [in] */ IVsCfgProviderEvents pCPE,
		/* [out] */ VSCOOKIE *pdwCookie)
	{
		mixin(LogCallMix);

		*pdwCookie = ++mLastCfgProviderEventsCookie;
		mCfgProviderEvents[mLastCfgProviderEventsCookie] = addref(pCPE);

		return S_OK;
	}

	override int UnadviseCfgProviderEvents( 
		/* [in] */ in VSCOOKIE dwCookie)
	{
		logCall("%s.UnadviseCfgProviderEvents(dwCookie=%s)", this, _toLog(dwCookie));

		if(dwCookie in mCfgProviderEvents)
		{
			release(mCfgProviderEvents[dwCookie]);
			mCfgProviderEvents.remove(dwCookie);
			return S_OK;
		}
		return returnError(E_FAIL);
	}

private:

	Project mProject;
	Config[] mConfigs;
	IVsCfgProviderEvents[VSCOOKIE] mCfgProviderEvents;
	VSCOOKIE mLastCfgProviderEventsCookie;
}

class Config :	DisposingComObject, 
		IVsProjectCfg2,
		IVsDebuggableProjectCfg,
		IVsBuildableProjectCfg,
		ISpecifyPropertyPages
{
	static GUID iid = { 0x402744c1, 0xe382, 0x4877, [ 0x9e, 0x38, 0x26, 0x9c, 0xb7, 0xa3, 0xb8, 0x9d ] };

	this(ConfigProvider provider, string name)
	{
		mProvider = provider;
		mProjectOptions = new ProjectOptions(name == "Debug");
		mBuilder = new CBuilderThread;
		mName = name;
	}

	override void Dispose()
	{
		mBuilder.Dispose();
	}

	override ULONG AddRef()
	{
		return super.AddRef();
	}
	override ULONG Release()
	{
		return super.Release();
	}

	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(Config) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectCfg2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(ISpecifyPropertyPages) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsDebuggableProjectCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsBuildableProjectCfg) (this, riid, pvObject))
			return S_OK;

		return super.QueryInterface(riid, pvObject);
	}

	// ISpecifyPropertyPages
	override int GetPages( /* [out] */ CAUUID *pPages)
	{
		mixin(LogCallMix);
		return PropertyPageFactory.GetProjectPages(pPages);
	}

	// IVsCfg
	override int get_DisplayName(BSTR *pbstrDisplayName)
	{
		logCall("%s.get_DisplayName(pbstrDisplayName=%s)", this, _toLog(pbstrDisplayName));

		*pbstrDisplayName = allocBSTR(mName ~ "|" ~ kPlatform);
		return S_OK;
	}
    
	override int get_IsDebugOnly(BOOL *pfIsDebugOnly)
	{
		logCall("%s.get_IsDebugOnly(pfIsDebugOnly=%s)", this, _toLog(pfIsDebugOnly));

		*pfIsDebugOnly = (mName == "Debug");
		return S_OK;
	}
    
	override int get_IsReleaseOnly(BOOL *pfIsReleaseOnly)
	{
		logCall("%s.get_IsReleaseOnly(pfIsReleaseOnly=%s)", this, _toLog(pfIsReleaseOnly));

		*pfIsReleaseOnly = (mName == "Release");
		return S_OK;
	}
    
	// IVsProjectCfg
	override int EnumOutputs(IVsEnumOutputs *ppIVsEnumOutputs)
	{
		mixin(LogCallMix);

		*ppIVsEnumOutputs = addref(new DEnumOutputs(this, 0));
		return S_OK;
	}

	override int OpenOutput(in wchar* szOutputCanonicalName, IVsOutput *ppIVsOutput)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_ProjectCfgProvider(/* [out] */ IVsProjectCfgProvider *ppIVsProjectCfgProvider)
	{
		mixin(LogCallMix);
		*ppIVsProjectCfgProvider = addref(mProvider);
		return S_OK;
	}

	override int get_BuildableProjectCfg( /* [out] */ IVsBuildableProjectCfg *ppIVsBuildableProjectCfg)
	{
		mixin(LogCallMix);
		*ppIVsBuildableProjectCfg = addref(this);
		return S_OK;
	}

	override int get_CanonicalName( /* [out] */ BSTR *pbstrCanonicalName)
	{
		logCall("get_CanonicalName(pbstrCanonicalName=%s)", _toLog(pbstrCanonicalName));
		return returnError(E_NOTIMPL);
	}

	override int get_Platform( /* [out] */ GUID *pguidPlatform)
	{
//		mixin(LogCallMix);
		*pguidPlatform = GUID_VS_PLATFORM_WIN32_X86;
		return S_OK;
	}

	override int get_IsPackaged( /* [out] */ BOOL *pfIsPackaged)
	{
		logCall("get_IsPackaged(pfIsPackaged=%s)", _toLog(pfIsPackaged));
		return returnError(E_NOTIMPL);
	}

	override int get_IsSpecifyingOutputSupported( /* [out] */ BOOL *pfIsSpecifyingOutputSupported)
	{
		logCall("get_IsSpecifyingOutputSupported(pfIsSpecifyingOutputSupported=%s)", _toLog(pfIsSpecifyingOutputSupported));
		return returnError(E_NOTIMPL);
	}

	override int get_TargetCodePage( /* [out] */ UINT *puiTargetCodePage)
	{
		logCall("get_TargetCodePage(puiTargetCodePage=%s)", _toLog(puiTargetCodePage));
		return returnError(E_NOTIMPL);
	}

	override int get_UpdateSequenceNumber( /* [out] */ ULARGE_INTEGER *puliUSN)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_RootURL( /* [out] */ BSTR *pbstrRootURL)
	{
		logCall("get_RootURL(pbstrRootURL=%s)", _toLog(pbstrRootURL));
		return returnError(E_NOTIMPL);
	}

	// IVsProjectCfg2
	override int get_CfgType( 
		/* [in] */ in IID* iidCfg,
		/* [iid_is][out] */ void **ppCfg)
	{
		mixin(LogCallMix);
		return QueryInterface(iidCfg, ppCfg);
	}

	override int get_OutputGroups( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ IVsOutputGroup *rgpcfg,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int OpenOutputGroup( 
		/* [in] */ in wchar* szCanonicalName,
		/* [out] */ IVsOutputGroup *ppIVsOutputGroup)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int OutputsRequireAppRoot( 
		/* [out] */ BOOL *pfRequiresAppRoot)
	{
		logCall("%s.OutputsRequireAppRoot(pfRequiresAppRoot=%s)", this, _toLog(pfRequiresAppRoot));
		return returnError(E_NOTIMPL);
	}

	override int get_VirtualRoot( 
		/* [out] */ BSTR *pbstrVRoot)
	{
		logCall("%s.get_VirtualRoot(pbstrVRoot=%s)", this, _toLog(pbstrVRoot));
		return returnError(E_NOTIMPL);
	}

	override int get_IsPrivate( 
		/* [out] */ BOOL *pfPrivate)
	{
		logCall("%s.get_IsPrivate(pfPrivate=%s)", this, _toLog(pfPrivate));
		return returnError(E_NOTIMPL);
	}

	// IVsDebuggableProjectCfg
	override int DebugLaunch( 
		/* [in] */ in VSDBGLAUNCHFLAGS grfLaunch)
	{
		logCall("%s.DebugLaunch(grfLaunch=%s)", this, _toLog(grfLaunch));

		string prg = mProjectOptions.replaceEnvironment(mProjectOptions.debugtarget, this);
		if (prg.length == 0)
			return S_OK;

		if(!isabs(prg))
			prg = GetProjectDir() ~ "\\" ~ prg;
		prg = quoteFilename(prg);

		string workdir = mProjectOptions.replaceEnvironment(mProjectOptions.debugworkingdir, this);
		if(!isabs(workdir))
			workdir = GetProjectDir() ~ "\\" ~ workdir;

		string args = mProjectOptions.replaceEnvironment(mProjectOptions.debugarguments, this);
		if(DBGLAUNCH_NoDebug & grfLaunch)
		{
			ShellExecuteW(null, null, toUTF16z(prg), toUTF16z(args), toUTF16z(workdir), SW_SHOWNORMAL);
			return(S_OK);
		}

		HRESULT hr = E_NOTIMPL;
		// When the debug target is the project build output, the project have to use 
		// IVsSolutionDebuggingAssistant2 to determine if the target was deployed.
		// The interface allows the project to find out where the outputs were deployed to 
		// and direct the debugger to the deployed locations as appropriate.
		// Projects start out their debugging sessions by calling MapOutputToDeployedURLs().

		// Here we do not use IVsSolutionDebuggingAssistant2 because our debug target is 
		// explicitly set in the project options and it is not built by the project.
		// For demo of how to use IVsSolutionDebuggingAssistant2 refer to MycPrj sample in the 
		// Environment SDK. 

		if(IVsDebugger srpVsDebugger = queryService!(IVsDebugger))
		{
			scope(exit) release(srpVsDebugger);

			VsDebugTargetInfo dbgi;

			dbgi.cbSize = VsDebugTargetInfo.sizeof;
			dbgi.bstrRemoteMachine = null;
			string remote = mProjectOptions.replaceEnvironment(mProjectOptions.debugremote, this);
			if(remote.length > 0)
				dbgi.bstrRemoteMachine = _toUTF16z(remote);

			dbgi.dlo = DLO_Custom;    // specifies how this process should be launched
			// clsidCustom is the clsid of the debug engine to use to launch the debugger
			*cast(GUID*)(&(dbgi.clsidCustom)+0) = GUID_COMPlusNativeEng;        // the mixed-mode debugger
			dbgi.bstrMdmRegisteredName = null; // used with DLO_AlreadyRunning. The name of the
			                                   // app as it is registered with the MDM.

			dbgi.bstrExe = _toUTF16z(prg);
			dbgi.bstrCurDir = _toUTF16z(workdir);
			dbgi.bstrArg = _toUTF16z(args);

			hr = srpVsDebugger.LaunchDebugTargets(1, &dbgi);
			if (FAILED(hr))
			{
				string msg = format("cannot launch debugger on %s", prg);
				mProvider.mProject.SetErrorInfo(E_FAIL, msg);
				hr = E_FAIL;
			}
		}
		return(hr);
	}

	override int QueryDebugLaunch( 
		/* [in] */ in VSDBGLAUNCHFLAGS grfLaunch,
		/* [out] */ BOOL *pfCanLaunch)
	{
//		mixin(LogCallMix);
		*pfCanLaunch = true;
		return S_OK; // returnError(E_NOTIMPL);
	}

	// IVsBuildableProjectCfg
	override int get_ProjectCfg( 
		/* [out] */ IVsProjectCfg *ppIVsProjectCfg)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AdviseBuildStatusCallback( 
		/* [in] */ IVsBuildStatusCallback pIVsBuildStatusCallback,
		/* [out] */ VSCOOKIE *pdwCookie)
	{
		mixin(LogCallMix);

		*pdwCookie = ++mLastBuildStatusCookie;
		mBuildStatusCallbacks[mLastBuildStatusCookie] = addref(pIVsBuildStatusCallback);
		mTicking[mLastBuildStatusCookie] = false;
		mStarted[mLastBuildStatusCookie] = false;
		return S_OK;
	}

	override int UnadviseBuildStatusCallback( 
		/* [in] */ in VSCOOKIE dwCookie)
	{
//		mixin(LogCallMix);

		if(dwCookie in mBuildStatusCallbacks)
		{
			release(mBuildStatusCallbacks[dwCookie]);
			mBuildStatusCallbacks.remove(dwCookie);
			mTicking.remove(dwCookie);
			mStarted.remove(dwCookie);
			return S_OK;
		}
		return returnError(E_FAIL);
	}

	override int StartBuild( 
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);

		if(dwOptions & VS_BUILDABLEPROJECTCFGOPTS_REBUILD)
			return mBuilder.Start(this, CBuilderThread.Operation.eRebuild, pIVsOutputWindowPane);
		return mBuilder.Start(this, CBuilderThread.Operation.eBuild, pIVsOutputWindowPane);
	}

	override int StartClean( 
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);
	
		return mBuilder.Start(this, CBuilderThread.Operation.eClean, pIVsOutputWindowPane);
	}

	override int StartUpToDateCheck( 
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);
	
		HRESULT rc = mBuilder.Start(this, CBuilderThread.Operation.eCheckUpToDate, pIVsOutputWindowPane);
		return rc == S_OK ? S_OK : E_FAIL; // E_FAIL used to indicate "not uptodate"
		//return returnError(E_NOTIMPL); //S_OK;
	}

	override int QueryStatus( 
		/* [out] */ BOOL *pfBuildDone)
	{
		logCall("%s.QueryStatus(pfBuildDone=%s)", this, _toLog(pfBuildDone));
		mBuilder.QueryStatus(pfBuildDone);
		return S_OK;
	}

	override int Stop( 
		/* [in] */ in BOOL fSync)
	{
		logCall("%s.Stop(fSync=%s)", this, _toLog(fSync));
		mBuilder.Stop(fSync);
		return S_OK;
	}

	override int Wait( 
		/* [in] */ in DWORD dwMilliseconds,
		/* [in] */ in BOOL fTickWhenMessageQNotEmpty)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int QueryStartBuild( 
		/* [in] */ in DWORD dwOptions,
		/* [optional][out] */ BOOL *pfSupported,
		/* [optional][out] */ BOOL *pfReady)
	{
		mixin(LogCallMix);
		if(pfSupported)
			*pfSupported = true;
		if(pfReady)
		{
			mBuilder.QueryStatus(pfReady);
		}
		return S_OK; // returnError(E_NOTIMPL);
	}

	override int QueryStartClean( 
		/* [in] */ in DWORD dwOptions,
		/* [optional][out] */ BOOL *pfSupported,
		/* [optional][out] */ BOOL *pfReady)
	{
		mixin(LogCallMix);
		if(pfSupported)
			*pfSupported = true;
		if(pfReady)
		{
			mBuilder.QueryStatus(pfReady);
		}
		return S_OK; // returnError(E_NOTIMPL);
	}

	override int QueryStartUpToDateCheck( 
		/* [in] */ in DWORD dwOptions,
		/* [optional][out] */ BOOL *pfSupported,
		/* [optional][out] */ BOOL *pfReady)
	{
		mixin(LogCallMix);
		if(pfSupported)
			*pfSupported = true;
		if(pfReady)
		{
			mBuilder.QueryStatus(pfReady);
		}
		return S_OK; // returnError(E_NOTIMPL);
	}

	//////////////////////////////////////////////////////////////////////////////
	void SetDirty()
	{
		mProvider.mProject.GetProjectNode().SetProjectFileDirty(true);
	}

	CProjectNode GetProjectNode() { return mProvider.mProject.GetProjectNode(); }
	string GetProjectPath() { return mProvider.mProject.GetFilename(); }
	string GetProjectDir() { return getDirName(mProvider.mProject.GetFilename()); }
	string GetProjectName() { return mProvider.mProject.GetProjectNode().GetName(); }

	ProjectOptions GetProjectOptions() { return mProjectOptions; }

	string GetTargetPath()
	{
		string exe = mProjectOptions.getTargetPath();
		return mProjectOptions.replaceEnvironment(exe, this);
	}

	string GetDependenciesPath()
	{
		string exe = mProjectOptions.getDependenciesPath();
		return mProjectOptions.replaceEnvironment(exe, this);
	}

	string GetCommandLinePath()
	{
		string exe = mProjectOptions.getCommandLinePath();
		return mProjectOptions.replaceEnvironment(exe, this);
	}

	string GetOutDir()
	{
		return mProjectOptions.replaceEnvironment(mProjectOptions.outdir, this);
	}

	string GetIntermediateDir()
	{
		return mProjectOptions.replaceEnvironment(mProjectOptions.objdir, this);
	}

	string[] GetDependencies(CFileNode file)
	{
		string tool = GetCompileTool(file);
		if(tool == "Custom" || tool == kToolResourceCompiler)
		{
			string dep = file.GetDependencies();
			dep = mProjectOptions.replaceEnvironment(dep, this, file.GetFilename());
			string[] deps = split(dep, ";");
			deps ~= file.GetFilename();
			string workdir = GetProjectDir();
			foreach(ref string s; deps)
				s = makeFilenameAbsolute(s, workdir);
			return deps;
		}
		return null;
	}

	bool isUptodate(CFileNode file)
	{
		string fcmd = GetCompileCommand(file);
		if(fcmd.length == 0)
			return true;

		string outfile = GetOutputFile(file);
		outfile = mProjectOptions.replaceEnvironment(outfile, this, file.GetFilename());

		string workdir = GetProjectDir();
		string cmdfile = makeFilenameAbsolute(outfile ~ "." ~ kCmdLogFileExtension, workdir);
		
		if(!compareCommandFile(cmdfile, fcmd))
			return false;

		string[] deps = GetDependencies(file);
		
		outfile = makeFilenameAbsolute(outfile, workdir);
		long targettm = getOldestFileTime( [ outfile ] );
		long sourcetm = getNewestFileTime(deps);

		return targettm > sourcetm;
	}

	bool customFilesUpToDate()
	{
		CHierNode node = searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					if(!isUptodate(file))
						return true;
				}
				return false;
			});
		
		return node is null;
	}

	static string GetCompileTool(CFileNode file)
	{
		string tool = file.GetTool();
		string fname = file.GetFilename();
		if(tool == "")
		{
			string ext = tolower(getExt(fname));
			if(ext == "d" || ext == "def" || ext == "lib" || ext == "obj" || ext == "res")
				tool = "DMD";
			else if(ext == "rc")
				tool = kToolResourceCompiler;
		}
		return tool;
	}

	string GetOutputFile(CFileNode file)
	{
		string tool = GetCompileTool(file);
		string fname;
		if(tool == "DMD")
			return file.GetFilename();
		if(tool == kToolResourceCompiler)
			fname = mProjectOptions.objdir ~ "\\" ~ getName(file.GetFilename()) ~ ".res";
		if(tool == "Custom")
			fname = file.GetOutFile();
		if(fname.length)
			fname = mProjectOptions.replaceEnvironment(fname, this, file.GetFilename());
		return fname;
	}

	string expandedAbsoluteFilename(string name)
	{
		string workdir = GetProjectDir();
		string expname = mProjectOptions.replaceEnvironment(name, this);
		string absname = makeFilenameAbsolute(expname, workdir);
		return absname;
	}
	
	string[] GetBuildFiles()
	{
		string workdir = normalizeDir(GetProjectDir());
		string outdir = normalizeDir(makeFilenameAbsolute(GetOutDir(), workdir));
		string intermediatedir = normalizeDir(makeFilenameAbsolute(GetIntermediateDir(), workdir));
		
		string target = makeFilenameAbsolute(GetTargetPath(), workdir);
		string cmdfile = makeFilenameAbsolute(GetCommandLinePath(), workdir);

		string[] files;
		files ~= target;
		files ~= cmdfile;
		files ~= cmdfile ~ ".rsp";
		files ~= makeFilenameAbsolute(GetDependenciesPath(), workdir);
		
		if(mProjectOptions.runCv2pdb)
		{
			files ~= target ~ "_cv";
			files ~= addExt(target, "pdb");
		}
		files ~= addExt(target, "map");

		if(mProjectOptions.createImplib)
			files ~= addExt(target, "lib");

		if(mProjectOptions.doDocComments)
		{
			if(mProjectOptions.docdir.length)
				files ~= expandedAbsoluteFilename(normalizeDir(mProjectOptions.docdir)) ~ "*.ddoc";
			if(mProjectOptions.docname.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.docname);
		}
		if(mProjectOptions.doHdrGeneration)
		{
			if(mProjectOptions.hdrdir.length)
				files ~= expandedAbsoluteFilename(normalizeDir(mProjectOptions.hdrdir)) ~ "*.di";
			if(mProjectOptions.hdrname.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.hdrname);
		}
		if(mProjectOptions.doXGeneration)
		{
			if(mProjectOptions.xfilename.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.xfilename);
		}

		string[] toclean = split(mProjectOptions.filesToClean, ";");
		foreach(s; toclean)
		{
			files ~= outdir ~ s;
			if(outdir != intermediatedir)
				files ~= intermediatedir ~ s;
		}
		searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					string outname = GetOutputFile(file);
					if (outname.length && outname != file.GetFilename())
					{
						files ~= makeFilenameAbsolute(outname, workdir);
						files ~= makeFilenameAbsolute(outname ~ "." ~ kCmdLogFileExtension, workdir);
					}
				}
				return false;
			});
		
		return files;
	}

	string GetCompileCommand(CFileNode file)
	{
		string tool = GetCompileTool(file);
		string cmd;
		string outfile = GetOutputFile(file);
		if(tool == kToolResourceCompiler)
		{
			cmd = "rc /fo" ~ quoteFilename(outfile);
			string include = Package.GetGlobalOptions().IncSearchPath;
			if(include.length)
			{
				include = mProjectOptions.replaceEnvironment(include, this);
				string[] incs = split(include, ";");
				foreach(string inc; incs)
					cmd ~= " /I" ~ quoteFilename(inc);
			}
			cmd ~= " " ~ file.GetFilename();
		}
		if(tool == "Custom")
		{
			cmd = file.GetCustomCmd();
		}
		if(cmd.length)
		{
			cmd = getEnvironmentChanges() ~ cmd ~ "\n";
			cmd ~= "if errorlevel 1 echo Building " ~ outfile ~ " failed!\n";
			cmd = mProjectOptions.replaceEnvironment(cmd, this, file.GetFilename());
		}
		return cmd;
	}

	string getEnvironmentChanges()
	{
		string cmd;
		GlobalOptions globOpt = Package.GetGlobalOptions();
		if(globOpt.ExeSearchPath.length)
			cmd ~= "set PATH=" ~ replaceCrLf(globOpt.ExeSearchPath) ~ ";%PATH%\n";
		if(globOpt.LibSearchPath.length)
			cmd ~= "set LIB=" ~ replaceCrLf(globOpt.LibSearchPath) ~ ";%LIB%\n";
		return cmd;
	}

	string getCommandLine()
	{
		string opt = mProjectOptions.buildCommandLine();
		if(mProjectOptions.additionalOptions.length)
			opt ~= " " ~ mProjectOptions.additionalOptions;

		string precmd = getEnvironmentChanges();

		string responsefile = GetCommandLinePath() ~ ".rsp";
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					string fname = GetOutputFile(file);
					if(fname.length)
						if(file.GetTool() != "Custom" || file.GetLinkOutput())
							files ~= quoteFilename(fname);
				}
				return false;
			});

		string[] libs = getLibsFromDependentProjects();
		files ~= libs;

		string fcmd = join(files, " ");
		if(fcmd.length > 100)
		{
			precmd ~= "\n";
			precmd ~= "echo " ~ files[0] ~ " >" ~ responsefile ~ "\n";
			for(int i = 1; i < files.length; i++)
				precmd ~= "echo " ~ files[i] ~ " >>" ~ responsefile ~ "\n";
			precmd ~= "\n";
			fcmd = " @" ~ responsefile;
		}
		else
			fcmd = " " ~ fcmd;
			
		string cmd = precmd ~ opt ~ fcmd;
		
		string cv2pdb = mProjectOptions.appendCv2pdb();
		if(cv2pdb.length)
		{
			cv2pdb = "echo Converting debug information...\n" ~ cv2pdb;
			cmd = cmd ~ "\nif errorlevel 1 goto xit\n" ~ cv2pdb;
		}

		string pre = strip(mProjectOptions.preBuildCommand);
		if(pre.length)
			cmd = pre ~ "\nif errorlevel 1 goto xit\n" ~ cmd;
		string post = strip(mProjectOptions.postBuildCommand);
		if(post.length)
			cmd = cmd ~ "\nif errorlevel 1 goto xit\n" ~ post;
		cmd ~= "\n:xit\n";
		cmd ~= "if errorlevel 1 echo Building " ~ GetTargetPath() ~ " failed!\n";

		return mProjectOptions.replaceEnvironment(cmd, this);
	}

	string[] getLibsFromDependentProjects()
	{
		string[] libs;
		auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
		if(!solutionBuildManager)
			return libs;

		scope(exit) release(solutionBuildManager);
		
		ULONG cActual;
		if(HRESULT hr = solutionBuildManager.GetProjectDependencies(mProvider.mProject, 0, null, &cActual))
			return libs;
		IVsHierarchy[] pHier = new IVsHierarchy [cActual];

		if(HRESULT hr = solutionBuildManager.GetProjectDependencies(mProvider.mProject, cActual, pHier.ptr, &cActual))
			return libs;
		
		for(int i = 0; i < cActual; i++)
		{
			IVsProjectCfg prjcfg;
			if(pHier[i].QueryInterface(&IVsProjectCfg.iid, cast(void**)&prjcfg) != S_OK)
			{
				IVsCfg cfg;
				IVsGetCfgProvider gcp;
				IVsCfgProvider cp;
				IVsCfgProvider2 cp2;
				if(pHier[i].QueryInterface(&IVsGetCfgProvider.iid, cast(void**)&gcp) == S_OK)
					gcp.GetCfgProvider(&cp);
				else
					pHier[i].QueryInterface(&IVsCfgProvider.iid, cast(void**)&cp);
				if(cp)
				{
					cp.QueryInterface(&IVsCfgProvider2.iid, cast(void**)&cp2);
					if(cp2)
					{
						cp2.GetCfgOfName(_toUTF16z(mName), _toUTF16z(kPlatform), &cfg);
						if(cfg)
							cfg.QueryInterface(&IVsProjectCfg.iid, cast(void**)&prjcfg);
					}
				}
				release(cfg);
				release(gcp);
				release(cp);
				release(cp2);
			}
			if(prjcfg)
			{
				scope(exit) release(prjcfg);

				IVsEnumOutputs eo;
				if(prjcfg.EnumOutputs(&eo) == S_OK)
				{
					scope(exit) release(eo);
					ULONG fetched;
					IVsOutput pIVsOutput;
					while(eo.Next(1, &pIVsOutput, &fetched) == S_OK && fetched == 1)
					{
						BSTR target;
						if(pIVsOutput.get_CanonicalName(&target) == S_OK)
						{
							string targ = detachBSTR(target);
							libs ~= quoteFilename(targ);
						}
						release(pIVsOutput);
					}
				}

			}
			release(pHier[i]);
		}
		return libs;
	}

	// tick the sink and check if build can continue or not.
	BOOL FFireTick()
	{
		foreach(cb; mBuildStatusCallbacks)
		{
			//if (m_rgfTicking[i])
			{
				BOOL fContinue = TRUE;
				HRESULT hr = cb.Tick(&fContinue);
				assert(SUCCEEDED(hr));
				if (!fContinue)
					return FALSE;
			}
		}
		return TRUE;
	}

	void FFireBuildBegin(ref BOOL fContinue)
	{
		fContinue = TRUE;
		foreach(key, cb; mBuildStatusCallbacks)
		{
			HRESULT hr = cb.BuildBegin(&fContinue);
			if(FAILED(hr) || !fContinue)
				break;
			mStarted[key] = true;
		}
	}

	void FFireBuildEnd(BOOL fSuccess)
	{
		// make a copy in case BuildEnd calls Unadvise
		IVsBuildStatusCallback[] cbs;
		foreach(key, cb; mBuildStatusCallbacks)
			if(mStarted[key])
			{
				cbs ~= cb;
				mStarted[key] = false;
			}

		foreach(cb; cbs)
		{
			HRESULT hr = cb.BuildEnd(fSuccess);
			assert(SUCCEEDED(hr));
		}
		Package.GetLibInfos().updateDefinitions();
	}

private:
	string mName;
	ConfigProvider mProvider;
	ProjectOptions mProjectOptions;
	CBuilderThread mBuilder;

	IVsBuildStatusCallback[VSCOOKIE] mBuildStatusCallbacks;
	bool[VSCOOKIE] mTicking;
	bool[VSCOOKIE] mStarted;

	VSCOOKIE mLastBuildStatusCookie;
};


GUID g_unmarshalCLSID  = { 1, 1, 0, [ 0x1,0x1,0x1,0x1, 0x1,0x1,0x1,0x1 ] };

class DEnumOutFactory : DComObject, IClassFactory
{
	HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface2!(IClassFactory) (this, IID_IClassFactory, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT CreateInstance(IUnknown UnkOuter, IID* riid, void** pvObject)
	{
		logCall("%s.CreateInstance(riid=%s)", this, _toLog(riid));

		assert(!UnkOuter);
		DEnumOutputs eo = new DEnumOutputs(null, 0);
		return eo.QueryInterface(riid, pvObject);
	}
	HRESULT LockServer(BOOL fLock)
	{
		return returnError(E_NOTIMPL);
	}
}

class DEnumOutputs : DComObject, IVsEnumOutputs, ICallFactory, IExternalConnection, IMarshal
{
	// {785486EE-2FB9-47f5-85A9-5790A60B5CEB}
	static const GUID iid = { 0x785486ee, 0x2fb9, 0x47f5, [ 0x85, 0xa9, 0x57, 0x90, 0xa6, 0xb, 0x5c, 0xeb ] };

	string[] mTargets;
	int mPos;

	this(Config cfg, int pos)
	{
		if(cfg)
			mTargets ~= makeFilenameAbsolute(cfg.GetTargetPath(), cfg.GetProjectDir());
		mPos = pos;
	}

	this(DEnumOutputs eo)
	{
		mTargets = eo.mTargets;
		mPos = eo.mPos;
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsEnumOutputs) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(ICallFactory) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IExternalConnection) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IMarshal) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT Reset()
	{
		mixin(LogCallMix);

		mPos = 0;
		return S_OK;
	}

	override HRESULT Next(in ULONG cElements, IVsOutput *rgpIVsOutput, ULONG *pcElementsFetched)
	{
		mixin(LogCallMix);

		if(mPos >= mTargets.length || cElements < 1)
		{
			if(pcElementsFetched)
				*pcElementsFetched = 0;
			return returnError(S_FALSE);
		}
		
		if(pcElementsFetched)
			*pcElementsFetched = 1;
		*rgpIVsOutput = addref(new VsOutput(mTargets[mPos]));
		mPos++;
		return S_OK;
	}

	override HRESULT Skip(in ULONG cElements)
	{
		logCall("%s.Skip(cElements=%s)", this, _toLog(cElements));

		mPos += cElements;
		if(mPos > mTargets.length)
		{
			mPos = mTargets.length;
			return S_FALSE;
		}
		return S_OK;
	}

	override HRESULT Clone(IVsEnumOutputs *ppIVsEnumOutputs)
	{
		mixin(LogCallMix);

		*ppIVsEnumOutputs = addref(new DEnumOutputs(this));
		return S_OK;
	}

	// ICallFactory
	override HRESULT CreateCall(
		/+[in]+/  in IID*              riid,
		/+[in]+/  IUnknown          pCtrlUnk,
		/+[in]+/  in IID*              riid2,
		/+[out, iid_is(riid2)]+/ IUnknown *ppv )
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	// IExternalConnection
	override DWORD AddConnection (
		/+[in]+/ in DWORD extconn,
		/+[in]+/ in DWORD reserved )
	{
		mixin(LogCallMix);

		return ++mExternalReferences;
	}

	override DWORD ReleaseConnection(
		/+[in]+/ in DWORD extconn,
		/+[in]+/ in DWORD reserved,
		/+[in]+/ in BOOL  fLastReleaseCloses )
	{
		mixin(LogCallMix);

		--mExternalReferences;
		if(mExternalReferences == 0)
			CoDisconnectObject(this, 0);

		return mExternalReferences;
	}

	int mExternalReferences;

	// IMarshall
	override HRESULT GetUnmarshalClass
		(
		/+[in]+/ in IID* riid,
		/+[in, unique]+/ in void *pv,
		/+[in]+/ in DWORD dwDestContext,
		/+[in, unique]+/ in void *pvDestContext,
		/+[in]+/ in DWORD mshlflags,
		/+[out]+/ CLSID *pCid
		)
	{
		mixin(LogCallMixNoRet);

		*cast(GUID*)pCid = g_unmarshalCLSID;
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override HRESULT GetMarshalSizeMax
		(
		/+[in]+/ in IID* riid,
		/+[in, unique]+/ in void *pv,
		/+[in]+/ in DWORD dwDestContext,
		/+[in, unique]+/ in void *pvDestContext,
		/+[in]+/ in DWORD mshlflags,
		/+[out]+/ DWORD *pSize
		)
	{
		mixin(LogCallMixNoRet);

		*pSize = 256;
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override HRESULT MarshalInterface
		(
		/+[in, unique]+/ IStream pStm,
		/+[in]+/ in IID* riid,
		/+[in, unique]+/ in void *pv,
		/+[in]+/ in DWORD dwDestContext,
		/+[in, unique]+/ in void *pvDestContext,
		/+[in]+/ in DWORD mshlflags
		)
	{
		mixin(LogCallMixNoRet);

		if(HRESULT hr = pStm.Write(cast(void*)&iid, iid.sizeof, null))
			return hr;
		int length = mTargets.length;
		if(HRESULT hr = pStm.Write(&length, length.sizeof, null))
			return hr;
		foreach(s; mTargets)
		{
			length = s.length;
			if(HRESULT hr = pStm.Write(&length, length.sizeof, null))
				return hr;
			if(HRESULT hr = pStm.Write(cast(void*)s.ptr, length, null))
				return hr;
		}

		if(HRESULT hr = pStm.Write(&mPos, mPos.sizeof, null))
			return hr;
		return S_OK;
	}

	override HRESULT UnmarshalInterface
		(
		/+[in, unique]+/ IStream pStm,
		/+[in]+/ in IID* riid,
		/+[out]+/ void **ppv
		)
	{
		mixin(LogCallMix);

		GUID miid;
		if(HRESULT hr = pStm.Read(&miid, iid.sizeof, null))
			return returnError(hr);
		assert(miid == iid);

		int cnt;
		if(HRESULT hr = pStm.Read(&cnt, cnt.sizeof, null))
			return hr;

		DEnumOutputs eo = new DEnumOutputs(null, 0);
		for(int i = 0; i < cnt; i++)
		{
			int length;
			if(HRESULT hr = pStm.Read(&length, length.sizeof, null))
				return hr;
			char[] s = new char[length];
			if(HRESULT hr = pStm.Read(s.ptr, length, null))
				return hr;
			eo.mTargets ~= cast(string) s;
		}

		if(HRESULT hr = pStm.Read(&eo.mPos, eo.mPos.sizeof, null))
			return hr;
		return eo.QueryInterface(riid, ppv);
	}

	override HRESULT ReleaseMarshalData
		(
		/+[in, unique]+/ IStream pStm
		)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override HRESULT DisconnectObject
		(
		/+[in]+/ in DWORD dwReserved
		)
	{
		logCall("%s.DisconnectObject(dwReserved=%s)", this, _toLog(dwReserved));
		return returnError(E_NOTIMPL);
	}

}

class VsOutput : DComObject, IVsOutput
{
	string mTarget;

	this(string target)
	{
		mTarget = target;
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsOutput) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT get_DisplayName(BSTR *pbstrDisplayName)
	{
		logCall("%s.get_DisplayName(pbstrDisplayName=%s)", this, _toLog(pbstrDisplayName));

		*pbstrDisplayName = allocBSTR(mTarget);
		return S_OK;
	}

	override HRESULT get_CanonicalName(BSTR *pbstrCanonicalName)
	{
		logCall("%s.get_CanonicalName(pbstrCanonicalName=%s)", this, _toLog(pbstrCanonicalName));
		*pbstrCanonicalName = allocBSTR(mTarget);
		return S_OK;
	}

	override HRESULT get_DeploySourceURL(BSTR *pbstrDeploySourceURL)
	{
		logCall("%s.get_DeploySourceURL(pbstrDeploySourceURL=%s)", this, _toLog(pbstrDeploySourceURL));

		*pbstrDeploySourceURL = allocBSTR("file:///" ~ mTarget);
		return S_OK;
	}

	// obsolete method
	override HRESULT get_Type(/+[out]+/ GUID *pguidType)
	{
		logCall("%s.get_Type(pguidType=%s)", this, _toLog(pguidType));
		*pguidType = GUID_NULL;
		return S_OK;
	}
}
