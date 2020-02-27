// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.config;

import std.string;
import std.conv;
import std.file;
import std.path;
import std.process : execute, ExecConfig = Config;
import std.utf;
import std.array;
import std.exception;
import std.windows.charset;
import core.stdc.string;

import stdext.path;
import stdext.array;
import stdext.file;
import stdext.string;
import stdext.util;

import xml = visuald.xmlwrap;

import visuald.windows;
import sdk.port.vsi;
import sdk.win32.objbase;
import sdk.win32.oleauto;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.vsshell110; // for IVsProfilableProjectCfg, etc

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.hierarchy;
import visuald.chiernode;
import visuald.dproject;
import visuald.dpackage;
import visuald.build;
import visuald.propertypage;
import visuald.stringutil;
import visuald.fileutil;
import visuald.lexutil;
import visuald.pkgutil;
import visuald.vdextensions;
import visuald.register;

version = hasOutputGroup;
enum usePipedmdForDeps = true;

// implementation of IVsProfilableProjectCfg is incomplete (profiler doesn't stop)
// but just providing proper output and debug information works for profiling as an executable
// version = hasProfilableConfig;

///////////////////////////////////////////////////////////////

const string[] kPlatforms = [ "Win32", "x64" ];

enum string kToolResourceCompiler = "Resource Compiler";
enum string kToolCpp = "C/C++";
const string kCmdLogFileExtension = "build";
const string kLinkLogFileExtension = "link";

version(hasProfilableConfig)
const GUID g_unmarshalTargetInfoCLSID = uuid("002a2de9-8bb6-484d-980f-7e4ad4084715");

///////////////////////////////////////////////////////////////

T clone(T)(T object)
{
	auto size = typeid(object).initializer.length;
	object = cast(T) ((cast(void*)object) [0..size].dup.ptr );
//	object.__monitor = null;
	return object;
}

///////////////////////////////////////////////////////////////

ubyte  toUbyte(string s) { return to!(ubyte)(s); }
float  toFloat(string s) { return to!(float)(s); }
string uintToString(uint x) { return to!(string)(x); }

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

enum Compiler
{
	DMD,
	GDC,
	LDC
}

enum OutputType
{
	Executable,
	StaticLib,
	DLL
};

enum Subsystem
{
	NotSet,
	Console,
	Windows,
	Native,
	Posix
};

enum CRuntime
{
	None,
	StaticRelease,
	StaticDebug,
	DynamicRelease,
	DynamicDebug,
}

class ProjectOptions
{
	bool obj;		// write object file
	bool link;		// perform link
	ubyte lib;		// write library file instead of object file(s) (1: static, 2:dynamic)
	ubyte subsystem;
	bool multiobj;		// break one object file into multiple ones
	bool oneobj;		// write one object file instead of multiple ones
	bool mscoff;		// use mscoff object files for Win32
	bool trace;		// insert profiling hooks
	bool quiet;		// suppress non-error messages
	bool verbose;		// verbose compile
	bool vtls;		// identify thread local variables
	bool vgc;		// List all gc allocations including hidden ones (DMD 2.066+)
	ubyte symdebug;		// insert debug symbolic information (0: none, 1: mago; obsolete: 2: VS, 3: as debugging)
	bool symdebugref;	// insert debug information for all referenced types, too
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
	bool errDeprecated;	// error when using deprecated features (2.061+)
	bool useAssert;		// generate runtime code for assert()'s
	bool useInvariants;	// generate class invariant checks
	bool useIn;		// generate precondition checks
	bool useOut;		// generate postcondition checks
	ubyte useArrayBounds;	// 0: no array bounds checks
	// 1: array bounds checks for safe functions only
	// 2: array bounds checks for all functions
	ubyte boundscheck;	// bounds checking (0: default, 1: on, 2: @safe only, 3: off)
	bool useSwitchError;	// check for switches without a default
	bool useUnitTests;	// generate unittest code
	bool useInline;		// inline expand functions
	ubyte release;		// build release version (0: -debug, 1: -release, 2: default)
	bool preservePaths;	// !=0 means don't strip path from source file
	bool warnings;		// enable warnings
	bool infowarnings;	// enable informational warnings
	bool checkProperty;	// enforce property syntax
	bool genStackFrame;	// always generate stack frame
	bool pic;		// generate position-independent-code for shared libs
	bool cov;		// generate code coverage data
	bool nofloat;		// code should not pull in floating point support
	bool ignoreUnsupportedPragmas;	// rather than error on them
	bool allinst;		// generate code for all template instantiations
	bool stackStomp;	// add stack stomp code

	bool betterC;
	bool dip25;
	bool dip1000;
	bool dip1008;
	bool dip1021;
	bool transition_field;         // list all non-mutable fields which occupy an object instance
	bool revert_import;            // revert to single phase name lookup
	bool preview_dtorfields;       // destruct fields of partially constructed objects
	bool transition_checkimports;  // give deprecation messages about 10378 anomalies
	bool transition_complex;       // give deprecation messages about all usages of complex or imaginary types
	bool preview_intpromote;       // fix integral promotions for unary + - ~ operators
	bool preview_fixAliasThis;     // when a symbol is resolved, check alias this scope before going to upper scopes
	bool preview_rvaluerefparam;   // enable rvalue arguments to ref parameters
	bool preview_nosharedaccess;   // disable access to shared memory objects
	bool preview_markdown;         // enable Markdown replacements in Ddoc
	bool transition_vmarkdown;     // list instances of Markdown replacements in Ddoc

	ubyte compiler;		// 0: DMD, 1: GDC, 2:LDC
	bool otherDMD;		// use explicit program path
	bool ccTransOpt;	// translate D options to C where applicable
	bool addDepImp;		// add import paths of dependent projects
	string cccmd;		// C/C++ compiler command prefix
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
	string modules_ddoc; // generate modules.ddoc for candydoc

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
	bool debuglib;      // use debug library

	string defaultlibname;	// default library for non-debug builds
	string debuglibname;	// default library for debug builds

	string moduleDepsFile;	// filename for deps output

	bool run;		// run resulting executable
	string runargs;		// arguments for executable

	ubyte runCv2pdb;		// run cv2pdb on executable (0: no, 1: suitable for debug engine, 2: yes)
	bool cv2pdbNoDemangle;	// do not demangle symbols
	bool cv2pdbEnumType;	// use enumerator type
	string pathCv2pdb;	// exe path for cv2pdb
	string cv2pdbOptions;	// more options for cv2pdb

	bool enableMixin;
	string mixinPath;

	enum
	{
		kCombinedCompileAndLink,
		kSingleFileCompilation,
		kSeparateCompileAndLink,
		kSeparateCompileOnly,
		kCompileThroughDub,
	}
	uint compilationModel = kCombinedCompileAndLink;

	bool isCombinedBuild() { return compilationModel == kCombinedCompileAndLink || compilationModel == kCompileThroughDub; }


	// Linker stuff
	string objfiles;
	string linkswitches;
	string libfiles;
	string libpaths;
	string deffile;
	string resfile;
	string exefile;
	bool   useStdLibPath;
	uint   cRuntime;
	bool   privatePhobos;

	string mapfile;
	string pdbfile;
	string impfile;

	string additionalOptions;
	string preBuildCommand;
	string postBuildCommand;

	// debug options
	string debugtarget;
	string debugarguments;
	string debugworkingdir;
	bool debugattach;
	string debugremote;
	ubyte debugEngine; // 0: mixed, 1: mago, 2: native
	bool debugStdOutToOutputWindow;
	bool pauseAfterRunning;

	string filesToClean;

	this(bool dbg, bool x64)
	{
		exefile = "$(OutDir)\\$(ProjectName).exe";
		outdir = "$(PlatformName)\\$(ConfigurationName)";
		objdir = "$(OutDir)";
		debugtarget = "$(TARGETPATH)";
		pathCv2pdb = "$(VisualDInstallDir)cv2pdb\\cv2pdb.exe";
		program = "$(DMDInstallDir)windows\\bin\\dmd.exe";
		xfilename = "$(IntDir)\\$(TargetName).json";
		mapfile = "$(IntDir)\\$(SafeProjectName).map";
		pdbfile = "$(IntDir)\\$(SafeProjectName).pdb";
		impfile = "$(IntDir)\\$(SafeProjectName).lib";
		mixinPath = "$(IntDir)\\$(SafeProjectName).mixin";
		cccmd = "$(CC) -c";
		ccTransOpt = true;
		doXGeneration = true;
		useStdLibPath = true;
		cRuntime = CRuntime.StaticRelease;
		debugEngine = 2;
		symdebugref = true;
		enableMixin = false;

		filesToClean = "*.obj;*.cmd;*.build;*.json;*.dep;*.tlog";
		setX64(x64);
		setDebug(dbg);
	}

	void setDebug(bool dbg)
	{
		runCv2pdb = dbg && !isX86_64 ? 1 : 0;
		symdebug = dbg ? 1 : 0;
		release = dbg ? 0 : 1;
		optimize = release == 1;
		useInline = release == 1;
	}
	void setX64(bool x64)
	{
		isX86_64 = x64;
		if(release != 1 && cRuntime == CRuntime.StaticRelease)
			cRuntime = CRuntime.StaticDebug;
	}

	override bool opEquals(Object obj) const
	{
		auto other = cast(ProjectOptions) obj;
		if (!other)
			return false;

		foreach (i, f; this.tupleof)
			if (this.tupleof[i] != other.tupleof[i])
				return false;
		return true;
	}

	string objectFileExtension() { return compiler != Compiler.GDC ? "obj" : "o"; }
	string otherCompilerPath() { return otherDMD ? program : null; }

	bool useMSVCRT()
	{
		return (compiler == Compiler.DMD && (isX86_64 || mscoff)) ||
		       (compiler == Compiler.LDC);
	}

	@property ref CompilerDirectories compilerDirectories()
	{
		switch(compiler)
		{
			default:
			case Compiler.DMD: return Package.GetGlobalOptions().DMD;
			case Compiler.GDC: return Package.GetGlobalOptions().GDC;
			case Compiler.LDC: return Package.GetGlobalOptions().LDC;
		}
	}

	bool isLDCforMinGW()
	{
		if (compiler != Compiler.LDC)
			return false;

		string installdir = Package.GetGlobalOptions().LDC.InstallDir;
		if (installdir.empty)
			return false;

		return std.file.exists(normalizeDir(installdir) ~ "lib/libphobos2-ldc.a");
	}

	// common options with building phobos.lib
	string dmdCommonCompileOptions()
	{
		string cmd = dmdFrontEndCompileOptions();

		if(isX86_64)
			cmd ~= " -m64";
		else if(mscoff)
			cmd ~= " -m32mscoff";
		if(verbose)
			cmd ~= " -v";

		if(symdebug)
			cmd ~= " -g"; // -gc no longer supported
		if (symdebug && symdebugref)
			cmd ~= " -gf";

		if(optimize)
			cmd ~= " -O";
		if(useInline)
			cmd ~= " -inline";
		if(genStackFrame)
			cmd ~= " -gs";
		if(stackStomp)
			cmd ~= " -gx";

		cmd ~= commonLanguageOptions();
		return cmd;
	}

	string dmdFrontEndCompileOptions()
	{
		string cmd;
		if(vtls)
			cmd ~= " -vtls";
		if(vgc)
			cmd ~= " -vgc";
		if(useDeprecated)
			cmd ~= " -d";
		else if(errDeprecated)
			cmd ~= " -de";
		if(release == 1)
			cmd ~= " -release";
		else if(release == 0)
			cmd ~= " -debug";
		if(warnings)
			cmd ~= " -w";
		if(infowarnings)
			cmd ~= " -wi";
		if(checkProperty)
			cmd ~= " -property";
		return cmd;
	}

	string dmdFrontEndOptions()
	{
		string cmd = commonLanguageOptions() ~ dmdFrontEndCompileOptions();
		return cmd;
	}

	string commonLanguageOptions()
	{
		string cmd;

		if (betterC)
			cmd ~= " -betterC";
		if (dip25)
			cmd ~= " -dip25";
		if (dip1000)
			cmd ~= " -dip1000";
		if (dip1008)
			cmd ~= " -dip1008";
		if (dip1021)
			cmd ~= " -preview=dip1021";
		if (transition_field)
			cmd ~= " -transition=field";
		if (revert_import)
			cmd ~= " -revert=import";
		if (preview_dtorfields)
			cmd ~= " -preview=dtorfields";
		if (transition_checkimports)
			cmd ~= " -transition=checkimports";
		if (transition_complex)
			cmd ~= " -transition=complex";
		if (preview_intpromote)
			cmd ~= " -preview=intpromote";
		if (preview_fixAliasThis)
			cmd ~= " -preview=fixAliasThis";
		if (preview_rvaluerefparam)
			cmd ~= " -preview=rvaluerefparam";
		if (preview_nosharedaccess)
			cmd ~= " -preview=nosharedaccess";
		if (preview_markdown)
			cmd ~= " -preview=markdown";
		if (transition_vmarkdown)
			cmd ~= " -transition=vmarkdown";

		return cmd;
	}

	string buildDMDCommandLine(Config cfg, bool compile, bool performLink, string deps, bool syntaxOnly)
	{
		string cmd;
		if(otherDMD && program.length)
			cmd = quoteNormalizeFilename(program);
		else
			cmd = "dmd";
		string memstats = Package.GetGlobalOptions().showMemUsage ? "-memStats " : null;
		if (deps && usePipedmdForDeps)
			memstats ~= "-deps " ~ quoteNormalizeFilename(deps) ~ " ";
		if(memstats || (performLink && Package.GetGlobalOptions().demangleError))
			cmd = "\"$(VisualDInstallDir)pipedmd.exe\" " ~ memstats ~ cmd;

		cmd ~= dmdCommonCompileOptions();

		if(lib == OutputType.StaticLib && performLink)
			cmd ~= " -lib";
		if(multiobj)
			cmd ~= " -multiobj";
		if(trace)
			cmd ~= " -profile";
		if(quiet)
			cmd ~= " -quiet";
		switch (boundscheck)
		{
			default: break;
			case 1: cmd ~= " -boundscheck=on"; break;
			case 2: cmd ~= " -boundscheck=safeonly"; break;
			case 3: cmd ~= " -boundscheck=off"; break;
		}
		if(useUnitTests)
			cmd ~= " -unittest";
		if(preservePaths)
			cmd ~= " -op";
		if(cov)
			cmd ~= " -cov";
		if(nofloat)
			cmd ~= " -nofloat";
		if(ignoreUnsupportedPragmas)
			cmd ~= " -ignore";
		if(allinst)
			cmd ~= " -allinst";

		if(privatePhobos)
			cmd ~= " -defaultlib=" ~ quoteFilename(normalizeDir(objdir) ~ "privatephobos.lib");

		if(enableMixin && compile)
			cmd ~= " -mixin=" ~ quoteNormalizeFilename(mixinPath);

		if(doDocComments && compile && !syntaxOnly)
		{
			cmd ~= " -D";
			if(docdir.length)
				cmd ~= " -Dd" ~ quoteNormalizeFilename(docdir);
			if(docname.length)
				cmd ~= " -Df" ~ quoteNormalizeFilename(docname);
		}

		if(doHdrGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -H";
			if(hdrdir.length)
				cmd ~= " -Hd" ~ quoteNormalizeFilename(hdrdir);
			if(hdrname.length)
				cmd ~= " -Hf" ~ quoteNormalizeFilename(hdrname);
		}

		if(doXGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -X";
			if(xfilename.length)
				cmd ~= " -Xf" ~ quoteNormalizeFilename(xfilename);
		}

		string[] imports = tokenizeArgs(imppath);
		if (addDepImp && cfg)
			foreach(dep; cfg.getImportsFromDependentProjects())
				imports.addunique(dep);
		foreach(imp; imports)
			if(strip(imp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(imp));

		string[] globalimports = tokenizeArgs(compilerDirectories.ImpSearchPath);
		foreach(gimp; globalimports)
			if(strip(gimp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(gimp));

		string[] fileImports = tokenizeArgs(fileImppath);
		foreach(imp; fileImports)
			if(strip(imp).length)
				cmd ~= " -J" ~ quoteNormalizeFilename(strip(imp));

		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(strip(ver).length)
				cmd ~= " -version=" ~ strip(ver);

		string[] ids = tokenizeArgs(debugids);
		foreach(id; ids)
			if(strip(id).length)
				cmd ~= " -debug=" ~ strip(id);

		if(deps && !syntaxOnly && !usePipedmdForDeps)
			cmd ~= " -deps=" ~ quoteNormalizeFilename(deps);
		if(performLink)
			cmd ~= linkCommandLine();
		return cmd;
	}

	string buildGDCCommandLine(Config cfg, bool compile, bool performLink, string deps, bool syntaxOnly)
	{
		string cmd;
		if(otherDMD && program.length)
			cmd = quoteNormalizeFilename(program);
		else
			cmd = "gdc";

		string memstats = Package.GetGlobalOptions().showMemUsage ? "-memStats " : null;
		if (deps && usePipedmdForDeps)
			memstats ~= "-deps " ~ quoteNormalizeFilename(deps) ~ " ";
		if(memstats ||(performLink && Package.GetGlobalOptions().demangleError))
			cmd = "\"$(VisualDInstallDir)pipedmd.exe\" -gdcmode " ~ memstats ~ cmd;

//		if(lib && performLink)
//			cmd ~= " -lib";
//		if(multiobj)
//			cmd ~= " -multiobj";
		if(lib == OutputType.DLL)
			cmd ~= " -mdll";
		if(subsystem == Subsystem.Windows)
			cmd ~= " -mwindows";
		else if(subsystem == Subsystem.Console)
			cmd ~= " -mconsole";
		if(isX86_64)
			cmd ~= " -m64";
		else
			cmd ~= " -m32";
		if(trace)
			cmd ~= " -pg";
//		if(quiet)
//			cmd ~= " -quiet";
		if(verbose)
			cmd ~= " -fd-verbose";
		if(vtls)
			cmd ~= " -fd-vtls";
		if(vgc)
			cmd ~= " -fd-vgc";
		if(symdebug)
			cmd ~= " -g";
		//if(symdebug == 2)
		//    cmd ~= " -fdebug-c";
		if(optimize)
			cmd ~= " -O3";
		if(useDeprecated)
			cmd ~= " -fdeprecated";
		if(boundscheck == 3)
			cmd ~= " -fno-bounds-check";
		if(useUnitTests)
			cmd ~= " -funittest";
		if(!useInline)
			cmd ~= " -fno-inline-functions";
		if(release == 1)
			cmd ~= " -frelease";
		else if (release == 0)
			cmd ~= " -fdebug";
//		if(preservePaths)
//			cmd ~= " -op";
		if(warnings)
			cmd ~= " -Werror";
		if(infowarnings)
			cmd ~= " -Wall";
		if(checkProperty)
			cmd ~= " -fproperty";
		if(genStackFrame)
			cmd ~= " -fno-omit-frame-pointer";
		if(cov)
			cmd ~= " -fprofile-arcs -ftest-coverage";
//		if(nofloat)
//			cmd ~= " -nofloat";
		if(ignoreUnsupportedPragmas)
			cmd ~= " -fignore-unknown-pragmas";

		if(doDocComments && compile && !syntaxOnly)
		{
			cmd ~= " -fdoc";
			if(docdir.length)
				cmd ~= " -fdoc-dir=" ~ quoteNormalizeFilename(docdir);
			if(docname.length)
				cmd ~= " -fdoc-file=" ~ quoteNormalizeFilename(docname);
		}

		if(doHdrGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -fintfc";
			if(hdrdir.length)
				cmd ~= " -fintfc-dir=" ~ quoteNormalizeFilename(hdrdir);
			if(hdrname.length)
				cmd ~= " -fintfc-file=" ~ quoteNormalizeFilename(hdrname);
		}

		if(doXGeneration && compile && !syntaxOnly)
		{
			string xfile = xfilename.length ? xfilename : "$(OUTDIR)\\$(SAFEPROJECTNAME).json";
			cmd ~= " -fXf=" ~ quoteNormalizeFilename(xfile);
		}

		string[] imports = tokenizeArgs(imppath);
		if (addDepImp && cfg)
			foreach(dep; cfg.getImportsFromDependentProjects())
				imports.addunique(dep);
		foreach(imp; imports)
			if(strip(imp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(imp));

		string[] globalimports = tokenizeArgs(compilerDirectories.ImpSearchPath);
		foreach(gimp; globalimports)
			if(strip(gimp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(gimp));

		string[] fileImports = tokenizeArgs(fileImppath);
		foreach(imp; fileImports)
			if(strip(imp).length)
				cmd ~= " -J" ~ quoteNormalizeFilename(strip(imp));

		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(strip(ver).length)
				cmd ~= " -fversion=" ~ strip(ver);

		string[] ids = tokenizeArgs(debugids);
		foreach(id; ids)
			if(strip(id).length)
				cmd ~= " -fdebug=" ~ strip(id);

		if(deps && !syntaxOnly && !usePipedmdForDeps)
			cmd ~= " -fdeps=" ~ quoteNormalizeFilename(deps);
		if(performLink)
			cmd ~= linkCommandLine();
		return cmd;
	}

	string buildLDCCommandLine(Config cfg, bool compile, bool performLink, string deps, bool syntaxOnly)
	{
		string cmd;
		if(otherDMD && program.length)
			cmd = quoteNormalizeFilename(program);
		else
			cmd = "ldc2";

		string memstats = Package.GetGlobalOptions().showMemUsage ? "-memStats " : null;
		if (deps && usePipedmdForDeps)
			memstats ~= "-deps " ~ quoteNormalizeFilename(deps) ~ " ";
		if(memstats || (performLink && Package.GetGlobalOptions().demangleError))
			cmd = "\"$(VisualDInstallDir)pipedmd.exe\" " ~ memstats ~ cmd;

		if(lib == OutputType.StaticLib && performLink)
			cmd ~= " -lib -oq -od=\"$(IntDir)\"";

		string[] addargs = additionalOptions.tokenizeArgs(false, true);
		bool hastriple = false;
		foreach(arg; addargs)
			hastriple = hastriple || arg.startsWith("-march=") || arg.startsWith("-mtriple=");
		if (!hastriple)
		{
			if(isX86_64)
				cmd ~= " -m64";
			else
				cmd ~= " -m32";
		}

		if(verbose)
			cmd ~= " -v";

		if(symdebug)
			cmd ~= " -g";

		if(optimize)
			cmd ~= " -O";
		if(useDeprecated)
			cmd ~= " -d";
		else if(errDeprecated)
			cmd ~= " -de";
		if(useUnitTests)
			cmd ~= " -unittest";
		if(release == 1)
			cmd ~= " -release";
		else if (release == 0)
			cmd ~= " -d-debug";
		if(preservePaths)
			cmd ~= " -op";
		if(warnings)
			cmd ~= " -w";
		if(infowarnings)
			cmd ~= " -wi";
		if(checkProperty)
			cmd ~= " -property";
		if(ignoreUnsupportedPragmas)
			cmd ~= " -ignore";
		if(allinst)
			cmd ~= " -allinst";
		switch (boundscheck)
		{
			default: break;
			case 1: cmd ~= " -boundscheck=on"; break;
			case 2: cmd ~= " -boundscheck=safeonly"; break;
			case 3: cmd ~= " -boundscheck=off"; break;
		}

		cmd ~= commonLanguageOptions();

		if(enableMixin && compile)
			cmd ~= " -mixin=" ~ quoteNormalizeFilename(mixinPath);

		if(doDocComments && compile && !syntaxOnly)
		{
			cmd ~= " -D";
			if(docdir.length)
				cmd ~= " -Dd=" ~ quoteNormalizeFilename(docdir);
			if(docname.length)
				cmd ~= " -Df=" ~ quoteNormalizeFilename(docname);
		}

		if(doHdrGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -H";
			if(hdrdir.length)
				cmd ~= " -Hd=" ~ quoteNormalizeFilename(hdrdir);
			if(hdrname.length)
				cmd ~= " -Hf=" ~ quoteNormalizeFilename(hdrname);
		}

		if(doXGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -X";
			if(xfilename.length)
				cmd ~= " -Xf=" ~ quoteNormalizeFilename(xfilename);
		}

		string[] imports = tokenizeArgs(imppath);
		if (addDepImp && cfg)
			foreach(dep; cfg.getImportsFromDependentProjects())
				imports.addunique(dep);
		foreach(imp; imports)
			if(strip(imp).length)
				cmd ~= " -I=" ~ quoteNormalizeFilename(strip(imp));

		string[] globalimports = tokenizeArgs(compilerDirectories.ImpSearchPath);
		foreach(gimp; globalimports)
			if(strip(gimp).length)
				cmd ~= " -I=" ~ quoteNormalizeFilename(strip(gimp));

		string[] fileImports = tokenizeArgs(fileImppath);
		foreach(imp; fileImports)
			if(strip(imp).length)
				cmd ~= " -J=" ~ quoteNormalizeFilename(strip(imp));

		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(strip(ver).length)
				cmd ~= " -d-version=" ~ strip(ver);

		string[] ids = tokenizeArgs(debugids);
		foreach(id; ids)
			if(strip(id).length)
				cmd ~= " -d-debug=" ~ strip(id);

		if(deps && !syntaxOnly && !usePipedmdForDeps)
			cmd ~= " -deps=" ~ quoteNormalizeFilename(deps);
		if(performLink)
			cmd ~= linkCommandLine();
		return cmd;
	}

	string buildCommandLine(Config cfg, bool compile, bool performLink, string deps, bool syntaxOnly = false)
	{
		if(compiler == Compiler.DMD)
			return buildDMDCommandLine(cfg, compile, performLink, deps, syntaxOnly);

		if(compiler == Compiler.LDC)
			return buildLDCCommandLine(cfg, compile, performLink, deps, syntaxOnly);

		if(!compile && performLink && lib == OutputType.StaticLib)
			return buildARCommandLine();

		return buildGDCCommandLine(cfg, compile, performLink, deps, syntaxOnly);
	}

	string buildARCommandLine()
	{
		string cmd = "ar cru " ~ quoteNormalizeFilename(getTargetPath());
		return cmd;
	}

	string linkDMDCommandLine(bool mslink)
	{
		string cmd;

		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile = getCvTargetPath();

		cmd ~= getOutputFileOption(dmdoutfile);
		if (!mslink)
			cmd ~= " -map " ~ quoteFilename(mapfile); // optlink always creates map file
		else if (mapverbosity > 0)
			cmd ~= " -L/MAP:" ~ quoteFilename(mapfile);

		switch(mapverbosity)
		{
			case 0: cmd ~= mslink ? "" : " -L/NOMAP"; break; // actually still creates map file
			case 1: cmd ~= mslink ? " -L/MAPINFO:EXPORTS" : " -L/MAP:ADDRESS"; break;
			case 2: break;
			case 3: cmd ~= mslink ? " -L/MAPINFO:EXPORTS" : " -L/MAP:FULL"; break; // mapinfo LINES removed in VS 2005
			case 4: cmd ~= mslink ? " -L/MAPINFO:EXPORTS" : " -L/MAP:FULL -L/XREF"; break; // mapinfo FIXUPS removed in VS.NET
			default: break;
		}

		if(lib != OutputType.StaticLib)
		{
			if(compiler == Compiler.LDC && debuglib)
				cmd ~= " -link-debuglib";

			if (symdebug && mslink)
				cmd ~= " -L/PDB:" ~ quoteFilename(pdbfile);

			if(createImplib)
				cmd ~= " -L/IMPLIB:" ~ quoteFilename(impfile);
			if(objfiles.length)
				cmd ~= " " ~ objfiles;
			if(deffile.length)
				cmd ~= " " ~ deffile;
			if(libfiles.length)
				cmd ~= " " ~ libfiles;
			if(resfile.length)
				cmd ~= " " ~ resfile;

			switch(subsystem)
			{
				default:
				case Subsystem.NotSet: break;
				case Subsystem.Console: cmd ~= " -L/SUBSYSTEM:CONSOLE"; break;
				case Subsystem.Windows: cmd ~= " -L/SUBSYSTEM:WINDOWS"; break;
				case Subsystem.Native:  cmd ~= " -L/SUBSYSTEM:NATIVE"; break;
				case Subsystem.Posix:   cmd ~= " -L/SUBSYSTEM:POSIX"; break;
			}
			if (mslink && lib == OutputType.DLL)
				cmd ~= " -L/DLL";

			if (mslink && Package.GetGlobalOptions().isVS2017OrLater)
				cmd ~= " -L/noopttls"; // update 15.3.1 moves TLS into _DATA segment
		}
		return cmd;
	}

	string linkGDCCommandLine()
	{
		string cmd;
		string linkeropt = " -Wl,";

		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile = getCvTargetPath();

		cmd ~= " -o " ~ quoteNormalizeFilename(dmdoutfile);
		switch(mapverbosity)
		{
			case 0: // no map
				break;
			default:
				cmd ~= linkeropt ~ "-Map=" ~ quoteFilename(mapfile);
				break;
		}

		string[] lpaths = tokenizeArgs(libpaths);
		if(useStdLibPath)
			lpaths ~= tokenizeArgs(isX86_64 ? compilerDirectories.LibSearchPath64 : compilerDirectories.LibSearchPath);
		else
			cmd ~= linkeropt ~ "-nostdlib";
		foreach(lp; lpaths)
			cmd ~= linkeropt ~ "-L," ~ quoteFilename(lp);

		if(lib != OutputType.StaticLib)
		{
			if(createImplib)
				cmd ~= " -L/IMPLIB:" ~ quoteFilename(impfile);
			if(objfiles.length)
				cmd ~= " " ~ objfiles;
			if(deffile.length)
				cmd ~= " " ~ deffile;
// added later in getCommandFileList
//			if(libfiles.length)
//				cmd ~= " " ~ libfiles;
			if(resfile.length)
				cmd ~= " " ~ resfile;
		}
		return cmd;
	}

	// mingw
	string linkLDCCommandLine()
	{
		string cmd;
		string linkeropt = " -L=";

		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile = getCvTargetPath();

		cmd ~= " -of=" ~ quoteNormalizeFilename(dmdoutfile);
		switch(mapverbosity)
		{
			case 0: // no map
				break;
			default:
				cmd ~= linkeropt ~ "-Map=" ~ quoteFilename(mapfile);
				break;
		}

		string[] lpaths = tokenizeArgs(libpaths);
		if(useStdLibPath)
			lpaths ~= tokenizeArgs(isX86_64 ? compilerDirectories.LibSearchPath64 : compilerDirectories.LibSearchPath);
		else
			cmd ~= linkeropt ~ "-nostdlib";
		foreach(lp; lpaths)
			cmd ~= linkeropt ~ "-L," ~ quoteFilename(lp);

		if(lib != OutputType.StaticLib)
		{
			if(createImplib)
				cmd ~= " -L" ~ quoteFilename(impfile);
			if(objfiles.length)
				cmd ~= " " ~ objfiles;
			if(deffile.length)
				cmd ~= " " ~ deffile;
			// added later in getCommandFileList
			//			if(libfiles.length)
			//				cmd ~= " " ~ libfiles;
			if(resfile.length)
				cmd ~= " " ~ resfile;
		}
		return cmd;
	}

	string optlinkCommandLine(string[] lnkfiles, string inioptions, string workdir, bool mslink, string plus)
	{
		string cmd;
		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile = getCvTargetPath();

		static string plusList(string[] lnkfiles, string ext, string sep)
		{
			if(ext.length == 0 || ext[0] != '.')
				ext = "." ~ ext;
			string s;
			foreach(i, file; lnkfiles)
			{
				file = unquoteArgument(file);
				if(toLower(extension(file)) != ext)
					continue;
				if(s.length > 0)
					s ~= sep;
				s ~= quoteNormalizeFilename(file);
			}
			return s;
		}

		inioptions ~= " " ~ additionalOptions.replace("\n", " ");
		string[] opts = tokenizeArgs(inioptions, false);
		opts = expandResponseFiles(opts, workdir);
		string addopts;
		foreach(ref opt; opts)
		{
			opt = unquoteArgument(opt);
			if(opt.startsWith("-L"))
				addopts ~= " " ~ quoteFilename(opt[2..$]);
			if(opt[0] != '-')
				lnkfiles ~= opt;
		}

		cmd ~= plusList(lnkfiles, objectFileExtension(), plus);
		cmd ~= mslink ? " /OUT:" : ",";
		cmd ~= quoteNormalizeFilename(dmdoutfile);
		if (mapverbosity > 0)
		{
			cmd ~= mslink ? " /MAP:" : ",";
			cmd ~= quoteFilename(mapfile);
		}
		else if (!mslink)
			cmd ~= "," ~ quoteFilename(mapfile);

		cmd ~= mslink ? " " : ",";

		string[] libs = tokenizeArgs(libfiles);
		libs ~= "user32.lib";
		libs ~= "kernel32.lib";
		if(useMSVCRT())
			if(std.file.exists(Package.GetGlobalOptions().getVCDir("lib\\legacy_stdio_definitions.lib", isX86_64, true)))
				libs ~= "legacy_stdio_definitions.lib";

		cmd ~= plusList(lnkfiles ~ libs, ".lib", plus);
		string[] lpaths = tokenizeArgs(libpaths);
		if(useStdLibPath)
			lpaths ~= tokenizeArgs(isX86_64 ? compilerDirectories.LibSearchPath64 :
								   mscoff   ? compilerDirectories.LibSearchPath32coff : compilerDirectories.LibSearchPath);
		foreach(lp; lpaths)
			if(mslink)
				cmd ~= " /LIBPATH:" ~ quoteFilename(normalizeDir(unquoteArgument(lp))[0..$-1]); // avoid trailing \ for quoted files
			else
				cmd ~= "+" ~ quoteFilename(normalizeDir(unquoteArgument(lp))); // optlink needs trailing \

		string def = deffile.length ? quoteNormalizeFilename(deffile) : plusList(lnkfiles, ".def", mslink ? " /DEF:" : plus);
		string res = resfile.length ? quoteNormalizeFilename(resfile) : plusList(lnkfiles, ".res", plus);
		if(mslink)
		{
			if(def.length)
				cmd ~= " /DEF:" ~ def;
			if(res.length)
				cmd ~= " " ~ res;
		}
		else
		{
			if(def.length || res.length)
				cmd ~= "," ~ def;
			if(res.length)
				cmd ~= "," ~ res;
		}

		if(!mslink)
			switch(mapverbosity)
			{
				case 0: cmd ~= "/NOMAP"; break; // actually still creates map file
				case 1: cmd ~= "/MAP:ADDRESS"; break;
				case 2: break;
				case 3: cmd ~= "/MAP:FULL"; break;
				case 4: cmd ~= "/MAP:FULL/XREF"; break;
				default: break;
			}

		if(symdebug)
		{
			if (mslink)
				cmd ~= " /DEBUG /PDB:" ~ quoteFilename(pdbfile);
			else
				cmd ~= "/CO";
		}
		cmd ~= mslink ? " /INCREMENTAL:NO /NOLOGO" : "/NOI/DELEXE";

		if(mslink)
		{
			if (Package.GetGlobalOptions().isVS2017OrLater)
				cmd ~= " /noopttls"; // update 15.3.1 moves TLS into _DATA segment

			switch(cRuntime)
			{
				case CRuntime.None:           cmd ~= " /NODEFAULTLIB:libcmt"; break;
				case CRuntime.StaticRelease:  break;
				case CRuntime.StaticDebug:    cmd ~= " /NODEFAULTLIB:libcmt libcmtd.lib"; break;
				case CRuntime.DynamicRelease: cmd ~= " /NODEFAULTLIB:libcmt msvcrt.lib"; break;
				case CRuntime.DynamicDebug:   cmd ~= " /NODEFAULTLIB:libcmt msvcrtd.lib"; break;
				default: break;
			}
		}

		if(lib != OutputType.StaticLib)
		{
			if(createImplib)
				cmd ~= " /IMPLIB:" ~ quoteFilename(impfile);

			switch(subsystem)
			{
				default:
				case Subsystem.NotSet: break;
				case Subsystem.Console: cmd ~= " /SUBSYSTEM:CONSOLE"; break;
				case Subsystem.Windows: cmd ~= " /SUBSYSTEM:WINDOWS"; break;
				case Subsystem.Native:  cmd ~= " /SUBSYSTEM:NATIVE"; break;
				case Subsystem.Posix:   cmd ~= " /SUBSYSTEM:POSIX"; break;
			}
		}
		if (mslink && lib == OutputType.DLL)
			cmd ~= " /DLL";

		cmd ~= addopts;
		return cmd;
	}

	string linkCommandLine()
	{
		if(compiler == Compiler.GDC)
			return linkGDCCommandLine();
		else if(isLDCforMinGW())
			return linkLDCCommandLine();
		else if(compiler == Compiler.LDC)
			return linkDMDCommandLine(true); // MS link
		else
			return linkDMDCommandLine(isX86_64);
	}

	string getObjectDirOption()
	{
		switch(compiler)
		{
			default:
			case Compiler.DMD: return " -od" ~ quoteFilename(objdir);
			case Compiler.LDC: return " -od=" ~ quoteFilename(objdir);
			case Compiler.GDC: return ""; // does not work with GDC
		}
	}

	string getOutputFileOption(string file)
	{
		switch(compiler)
		{
			default:
			case Compiler.DMD: return " -of" ~ quoteFilename(file);
			case Compiler.LDC: return " -of=" ~ quoteFilename(file);
			case Compiler.GDC: return " -o " ~ quoteFilename(file);
		}
	}

	string getCppCommandLine(string file, bool setenv)
	{
		int cc; // 0-3 for dmc,cl,clang,gdc
		switch(compiler)
		{
			default:
			case Compiler.DMD: cc = (isX86_64 || mscoff ? 1 : 0); break;
			case Compiler.LDC: cc = (isLDCforMinGW() ? 2 : 1); break;
			case Compiler.GDC: cc = 3; break;
		}

		string cmd = cccmd;
		if(cc == 1 && setenv)
		{
			if (std.file.exists(Package.GetGlobalOptions().VCInstallDir ~ "vcvarsall.bat"))
				cmd = `call "%VCINSTALLDIR%\vcvarsall.bat" ` ~ (isX86_64 ? "x86_amd64" : "x86") ~ "\n" ~ cmd;
			else if (std.file.exists(Package.GetGlobalOptions().VCInstallDir ~ r"Auxiliary\Build\vcvarsall.bat"))
				cmd = "pushd .\n" ~ `call "%VCINSTALLDIR%\Auxiliary\Build\vcvarsall.bat" ` ~ (isX86_64 ? "x86_amd64" : "x86") ~ "\n" ~ "popd\n" ~ cmd;
		}

		static string[4] outObj = [ " -o", " -Fo", " -o", " -o " ];
		if (file.length)
			cmd ~= outObj[cc] ~ quoteFilename(file);

		if (!ccTransOpt)
			return cmd;

		static string[4] dbg = [ " -g", " -Z7", " -g", " -g" ];
		if(symdebug)
			cmd ~= dbg[cc];

		if (release == 1)
			cmd ~= " -DNDEBUG";

		static string[4] opt = [ " -O", " -Ox", " -O3", " -O3" ];
		if(optimize)
			cmd ~= opt[cc];

		if (quiet && cc == 1)
			cmd ~= " /NOLOGO";

		return cmd;
	}

	string getDependenciesFileOption(string file)
	{
		if(compiler == Compiler.GDC)
			return " -fdeps=" ~ quoteFilename(file);
		else
			return " -deps=" ~ quoteFilename(file);
	}

	string getAdditionalLinkOptions()
	{
		if(compiler != Compiler.DMD && lib == OutputType.StaticLib)
			return ""; // no options to ar

		return additionalOptions.replace("\n", " "); // always filtered through compiler
	}

	string getTargetPath()
	{
		if(exefile.length)
			return normalizePath(exefile);
		if(lib == OutputType.StaticLib)
			return "$(OutDir)\\$(ProjectName).lib";
		return "$(OutDir)\\$(ProjectName).exe";
	}

	string getCvTargetPath()
	{
		if(exefile.length)
			return "$(IntDir)\\" ~ baseName(exefile) ~ "_cv";
		return "$(IntDir)\\$(ProjectName).exe_cv";
	}

	string getDependenciesPath()
	{
		return normalizeDir(objdir) ~ "$(ProjectName).dep";
	}

	string getCommandLinePath(bool link)
	{
		return normalizeDir(objdir) ~ "$(ProjectName)." ~ (link ? kLinkLogFileExtension : kCmdLogFileExtension);
	}

	// "linking" includes building library (through ar with GDC, internal with DMD)
	bool doSeparateLink()
	{
		if(compilationModel == ProjectOptions.kSeparateCompileOnly)
			return false;
		if(compilationModel == ProjectOptions.kCompileThroughDub)
			return false;

		bool separateLink = compilationModel == ProjectOptions.kSeparateCompileAndLink;
		if (compiler == Compiler.GDC && lib == OutputType.StaticLib)
			separateLink = true;

		if (compiler == Compiler.DMD && lib != OutputType.StaticLib)
		{
			if(Package.GetGlobalOptions().optlinkDeps)
				separateLink = true;
			else if(isX86_64 && Package.GetGlobalOptions().DMD.overrideIni64)
				separateLink = true;
			else if(!isX86_64 && mscoff && Package.GetGlobalOptions().DMD.overrideIni32coff)
				separateLink = true;
		}
		return separateLink;
	}

	bool callLinkerDirectly()
	{
		bool dmdlink = compiler == Compiler.DMD && doSeparateLink() && lib != OutputType.StaticLib;
		return dmdlink; // && !isX86_64;
	}

	bool usesCv2pdb()
	{
		if (runCv2pdb == 2)
			return true;
		if (runCv2pdb == 0)
			return false;
		if(compiler == Compiler.DMD && (isX86_64 || mscoff))
			return false; // should generate correct debug info directly
		if(compiler == Compiler.LDC && !isLDCforMinGW())
			return false; // should generate correct debug info directly
		if (!symdebug || lib == OutputType.StaticLib)
			return false;
		return (debugEngine != 1); // not for mago
	}

	bool usesMSLink()
	{
		if(compiler == Compiler.DMD && (isX86_64 || mscoff))
			return true;
		if(compiler == Compiler.LDC)
			return true;
		return false;
	}

	string appendCv2pdb()
	{
		if(usesCv2pdb())
		{
			string target = getTargetPath();
			string cmd = quoteFilename(pathCv2pdb);
			if(cv2pdbEnumType)
				cmd ~= " -e";
			if(cv2pdbNoDemangle)
				cmd ~= " -n";
			if(cv2pdbOptions.length)
				cmd ~= " " ~ cv2pdbOptions;

			cmd ~= " " ~ quoteFilename(getCvTargetPath()) ~ " " ~ quoteFilename(target) ~ " " ~ quoteFilename(pdbfile);
			return cmd;
		}
		return "";
	}

	string replaceEnvironment(string cmd, Config config, string inputfile = "", string outputfile = "")
	{
		if(indexOf(cmd, '$') < 0)
			return cmd;

		string configname = config.mName;
		string projectpath = config.GetProjectPath();
		string safeprojectpath = projectpath.replace(" ", "_");

		string[string] replacements;

		string solutionpath = GetSolutionFilename();
		if(solutionpath.length)
			addFileMacros(solutionpath, "SOLUTION", replacements);
		replacements["PLATFORMNAME"] = config.mPlatform;
		replacements["PLATFORM"] = config.mPlatform;
		addFileMacros(projectpath, "PROJECT", replacements);
		replacements["PROJECTNAME"] = config.GetProjectName();
		addFileMacros(safeprojectpath, "SAFEPROJECT", replacements);
		replacements["SAFEPROJECTNAME"] = config.GetProjectName().replace(" ", "_");
		addFileMacros(inputfile.length ? inputfile : projectpath, "INPUT", replacements);
		replacements["CONFIGURATIONNAME"] = configname;
		replacements["CONFIGURATION"] = configname;
		replacements["OUTDIR"] = normalizePath(outdir);
		replacements["INTDIR"] = normalizePath(objdir);
		Package.GetGlobalOptions().addReplacements(replacements);

		replacements["CC"] = config.GetCppCompiler();

		string targetpath = outputfile.length ? outputfile : getTargetPath();
		string target = replaceMacros(targetpath, replacements);
		addFileMacros(target, "TARGET", replacements);

		return replaceMacros(cmd, replacements);
	}

	void writeXML(xml.Element elem)
	{
		elem ~= new xml.Element("obj", toElem(obj));
		elem ~= new xml.Element("link", toElem(link));
		elem ~= new xml.Element("lib", toElem(lib));
		elem ~= new xml.Element("subsystem", toElem(subsystem));
		elem ~= new xml.Element("multiobj", toElem(multiobj));
		elem ~= new xml.Element("singleFileCompilation", toElem(compilationModel));
		elem ~= new xml.Element("oneobj", toElem(oneobj));
		elem ~= new xml.Element("mscoff", toElem(mscoff));
		elem ~= new xml.Element("trace", toElem(trace));
		elem ~= new xml.Element("quiet", toElem(quiet));
		elem ~= new xml.Element("verbose", toElem(verbose));
		elem ~= new xml.Element("vtls", toElem(vtls));
		elem ~= new xml.Element("vgc", toElem(vgc));
		elem ~= new xml.Element("symdebug", toElem(symdebug));
		elem ~= new xml.Element("symdebugref", toElem(symdebugref));
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
		elem ~= new xml.Element("errDeprecated", toElem(errDeprecated));
		elem ~= new xml.Element("useAssert", toElem(useAssert));
		elem ~= new xml.Element("useInvariants", toElem(useInvariants));
		elem ~= new xml.Element("useIn", toElem(useIn));
		elem ~= new xml.Element("useOut", toElem(useOut));
		elem ~= new xml.Element("useArrayBounds", toElem(useArrayBounds));
		elem ~= new xml.Element("boundscheck", toElem(boundscheck));
		elem ~= new xml.Element("useSwitchError", toElem(useSwitchError));
		elem ~= new xml.Element("useUnitTests", toElem(useUnitTests));
		elem ~= new xml.Element("useInline", toElem(useInline));
		elem ~= new xml.Element("release", toElem(release));
		elem ~= new xml.Element("preservePaths", toElem(preservePaths));
		elem ~= new xml.Element("warnings", toElem(warnings));
		elem ~= new xml.Element("infowarnings", toElem(infowarnings));
		elem ~= new xml.Element("checkProperty", toElem(checkProperty));
		elem ~= new xml.Element("genStackFrame", toElem(genStackFrame));
		elem ~= new xml.Element("pic", toElem(pic));
		elem ~= new xml.Element("cov", toElem(cov));
		elem ~= new xml.Element("nofloat", toElem(nofloat));
		elem ~= new xml.Element("ignoreUnsupportedPragmas", toElem(ignoreUnsupportedPragmas));
		elem ~= new xml.Element("allinst", toElem(allinst));
		elem ~= new xml.Element("stackStomp", toElem(stackStomp));

		elem ~= new xml.Element("betterC", toElem(betterC));
		elem ~= new xml.Element("dip25", toElem(dip25));
		elem ~= new xml.Element("dip1000", toElem(dip1000));
		elem ~= new xml.Element("dip1008", toElem(dip1008));
		elem ~= new xml.Element("dip1021", toElem(dip1021));
		elem ~= new xml.Element("transition_field", toElem(transition_field));
		elem ~= new xml.Element("revert_import", toElem(revert_import));
		elem ~= new xml.Element("preview_dtorfields", toElem(preview_dtorfields));
		elem ~= new xml.Element("transition_checkimports", toElem(transition_checkimports));
		elem ~= new xml.Element("transition_complex", toElem(transition_complex));
		elem ~= new xml.Element("preview_intpromote", toElem(preview_intpromote));
		elem ~= new xml.Element("preview_fixAliasThis", toElem(preview_fixAliasThis));
		elem ~= new xml.Element("preview_markdown", toElem(preview_markdown));
		elem ~= new xml.Element("preview_rvaluerefparam", toElem(preview_rvaluerefparam));
		elem ~= new xml.Element("preview_nosharedaccess", toElem(preview_nosharedaccess));
		elem ~= new xml.Element("transition_vmarkdown", toElem(transition_vmarkdown));

		elem ~= new xml.Element("compiler", toElem(compiler));
		elem ~= new xml.Element("otherDMD", toElem(otherDMD));
		elem ~= new xml.Element("cccmd", toElem(cccmd));
		elem ~= new xml.Element("ccTransOpt", toElem(ccTransOpt));
		elem ~= new xml.Element("addDepImp", toElem(addDepImp));
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
		elem ~= new xml.Element("modules_ddoc", toElem(modules_ddoc));
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
		elem ~= new xml.Element("debuglib", toElem(debuglib));

		elem ~= new xml.Element("defaultlibname", toElem(defaultlibname));
		elem ~= new xml.Element("debuglibname", toElem(debuglibname));

		elem ~= new xml.Element("moduleDepsFile", toElem(moduleDepsFile));

		elem ~= new xml.Element("run", toElem(run));
		elem ~= new xml.Element("runargs", toElem(runargs));

		elem ~= new xml.Element("runCv2pdb", toElem(runCv2pdb));
		elem ~= new xml.Element("pathCv2pdb", toElem(pathCv2pdb));
		elem ~= new xml.Element("cv2pdbNoDemangle", toElem(cv2pdbNoDemangle));
		elem ~= new xml.Element("cv2pdbEnumType", toElem(cv2pdbEnumType));
		elem ~= new xml.Element("cv2pdbOptions", toElem(cv2pdbOptions));

		elem ~= new xml.Element("enableMixin", toElem(enableMixin));
		elem ~= new xml.Element("mixinPath", toElem(mixinPath));

		// Linker stuff
		elem ~= new xml.Element("objfiles", toElem(objfiles));
		elem ~= new xml.Element("linkswitches", toElem(linkswitches));
		elem ~= new xml.Element("libfiles", toElem(libfiles));
		elem ~= new xml.Element("libpaths", toElem(libpaths));
		elem ~= new xml.Element("deffile", toElem(deffile));
		elem ~= new xml.Element("resfile", toElem(resfile));
		elem ~= new xml.Element("exefile", toElem(exefile));
		elem ~= new xml.Element("pdbfile", toElem(pdbfile));
		elem ~= new xml.Element("impfile", toElem(impfile));
		elem ~= new xml.Element("mapfile", toElem(mapfile));
		elem ~= new xml.Element("useStdLibPath", toElem(useStdLibPath));
		elem ~= new xml.Element("cRuntime", toElem(cRuntime));
		elem ~= new xml.Element("privatePhobos", toElem(privatePhobos));

		elem ~= new xml.Element("additionalOptions", toElem(additionalOptions));
		elem ~= new xml.Element("preBuildCommand", toElem(preBuildCommand));
		elem ~= new xml.Element("postBuildCommand", toElem(postBuildCommand));

		elem ~= new xml.Element("filesToClean", toElem(filesToClean));
	}
	void writeDebuggerXML(xml.Element elem)
	{
		elem ~= new xml.Element("debugtarget", toElem(debugtarget));
		elem ~= new xml.Element("debugarguments", toElem(debugarguments));
		elem ~= new xml.Element("debugworkingdir", toElem(debugworkingdir));
		elem ~= new xml.Element("debugattach", toElem(debugattach));
		elem ~= new xml.Element("debugremote", toElem(debugremote));
		elem ~= new xml.Element("debugEngine", toElem(debugEngine));
		elem ~= new xml.Element("debugStdOutToOutputWindow", toElem(debugStdOutToOutputWindow));
		elem ~= new xml.Element("pauseAfterRunning", toElem(pauseAfterRunning));
	}

	void parseXML(xml.Element elem)
	{
		fromElem(elem, "obj", obj);
		fromElem(elem, "link", link);
		fromElem(elem, "lib", lib);
		fromElem(elem, "subsystem", subsystem);
		fromElem(elem, "multiobj", multiobj);
		fromElem(elem, "singleFileCompilation", compilationModel);
		fromElem(elem, "oneobj", oneobj);
		fromElem(elem, "mscoff", mscoff);
		fromElem(elem, "trace", trace);
		fromElem(elem, "quiet", quiet);
		fromElem(elem, "verbose", verbose);
		fromElem(elem, "vtls", vtls);
		fromElem(elem, "vgc", vgc);
		fromElem(elem, "symdebug", symdebug);
		fromElem(elem, "symdebugref", symdebugref);
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
		fromElem(elem, "errDeprecated", errDeprecated);
		fromElem(elem, "useAssert", useAssert);
		fromElem(elem, "useInvariants", useInvariants);
		fromElem(elem, "useIn", useIn);
		fromElem(elem, "useOut", useOut);
		fromElem(elem, "useArrayBounds", useArrayBounds);
		bool noboundscheck;
		fromElem(elem, "noboundscheck", noboundscheck);
		fromElem(elem, "boundscheck", boundscheck);
		if (boundscheck == 0 && noboundscheck)
			boundscheck = 3;
		fromElem(elem, "useSwitchError", useSwitchError);
		fromElem(elem, "useUnitTests", useUnitTests);
		fromElem(elem, "useInline", useInline);
		fromElem(elem, "release", release);
		fromElem(elem, "preservePaths", preservePaths);
		fromElem(elem, "warnings", warnings);
		fromElem(elem, "infowarnings", infowarnings);
		fromElem(elem, "checkProperty", checkProperty);
		fromElem(elem, "genStackFrame", genStackFrame);
		fromElem(elem, "pic", pic);
		fromElem(elem, "cov", cov);
		fromElem(elem, "nofloat", nofloat);
		fromElem(elem, "ignoreUnsupportedPragmas", ignoreUnsupportedPragmas);
		fromElem(elem, "allinst", allinst);
		fromElem(elem, "stackStomp", stackStomp);

		fromElem(elem, "betterC", betterC);
		fromElem(elem, "dip25", dip25);
		fromElem(elem, "dip1000", dip1000);
		fromElem(elem, "dip1008", dip1008);
		fromElem(elem, "dip1021", dip1021);
		fromElem(elem, "transition_field", transition_field);
		fromElem(elem, "revert_import", revert_import);
		fromElem(elem, "preview_dtorfields", preview_dtorfields);
		fromElem(elem, "transition_checkimports", transition_checkimports);
		fromElem(elem, "transition_complex", transition_complex);
		fromElem(elem, "preview_intpromote", preview_intpromote);
		fromElem(elem, "preview_fixAliasThis", preview_fixAliasThis);
		fromElem(elem, "preview_rvaluerefparam", preview_rvaluerefparam);
		fromElem(elem, "preview_nosharedaccess", preview_nosharedaccess);
		fromElem(elem, "preview_markdown", preview_markdown);
		fromElem(elem, "transition_vmarkdown", transition_vmarkdown);

		fromElem(elem, "compiler", compiler);
		fromElem(elem, "otherDMD", otherDMD);
		fromElem(elem, "cccmd", cccmd);
		fromElem(elem, "ccTransOpt", ccTransOpt);
		fromElem(elem, "addDepImp", addDepImp);
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
		fromElem(elem, "modules_ddoc", modules_ddoc);
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
		fromElem(elem, "debuglib", debuglib);

		fromElem(elem, "defaultlibname", defaultlibname);
		fromElem(elem, "debuglibname", debuglibname);

		fromElem(elem, "moduleDepsFile", moduleDepsFile);

		fromElem(elem, "run", run);
		fromElem(elem, "runargs", runargs);

		fromElem(elem, "runCv2pdb", runCv2pdb);
		fromElem(elem, "pathCv2pdb", pathCv2pdb);
		fromElem(elem, "cv2pdbNoDemangle", cv2pdbNoDemangle);
		fromElem(elem, "cv2pdbEnumType", cv2pdbEnumType);
		fromElem(elem, "cv2pdbOptions", cv2pdbOptions);

		fromElem(elem, "enableMixin", enableMixin);
		fromElem(elem, "mixinPath", mixinPath);

		// Linker stuff
		fromElem(elem, "objfiles", objfiles);
		fromElem(elem, "linkswitches", linkswitches);
		fromElem(elem, "libfiles", libfiles);
		fromElem(elem, "libpaths", libpaths);
		fromElem(elem, "deffile", deffile);
		fromElem(elem, "resfile", resfile);
		fromElem(elem, "exefile", exefile);
		fromElem(elem, "pdbfile", pdbfile);
		fromElem(elem, "impfile", impfile);
		fromElem(elem, "mapfile", mapfile);
		fromElem(elem, "useStdLibPath", useStdLibPath);
		fromElem(elem, "cRuntime", cRuntime);
		fromElem(elem, "privatePhobos", privatePhobos);

		fromElem(elem, "additionalOptions", additionalOptions);
		fromElem(elem, "preBuildCommand", preBuildCommand);
		fromElem(elem, "postBuildCommand", postBuildCommand);

		fromElem(elem, "debugtarget", debugtarget);
		fromElem(elem, "debugarguments", debugarguments);
		fromElem(elem, "debugworkingdir", debugworkingdir);
		fromElem(elem, "debugattach", debugattach);
		fromElem(elem, "debugremote", debugremote);
		fromElem(elem, "debugEngine", debugEngine);
		fromElem(elem, "debugStdOutToOutputWindow", debugStdOutToOutputWindow);
		fromElem(elem, "pauseAfterRunning", pauseAfterRunning);

		fromElem(elem, "filesToClean", filesToClean);
	}
}

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

	Config addConfig(string name, string platform)
	{
		Config cfg = newCom!Config(this, name, platform);
		mConfigs ~= addref(cfg);
		return cfg;
	}

	void addConfigsToXml(xml.Document doc)
	{
		foreach(Config cfg; mConfigs)
		{
			auto config = new xml.Element("Config");
			xml.setAttribute(config, "name", cfg.mName);
			xml.setAttribute(config, "platform", cfg.mPlatform);

			ProjectOptions opt = cfg.GetProjectOptions();
			opt.writeXML(config);
			doc ~= config;
		}
	}

	void addMSBuildConfigsToXml(xml.Document doc)
	{
		foreach(Config cfg; mConfigs)
		{
			auto config = new xml.Element("PropertyGroup");
			string cond = "'$(Configuration)|$(Platform)'=='" ~ cfg.mName ~ "|" ~ cfg.mPlatform ~ "'";
			xml.setAttribute(config, "Condition", cond);

			ProjectOptions opt = cfg.GetProjectOptions();
			opt.writeXML(config);
			doc ~= config;
		}
	}

	override void Dispose()
	{
		foreach(Config cfg; mConfigs)
			release(cfg);
		mConfigs = mConfigs.init;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
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
		debug(FULL_DBG) mixin(LogCallMix);

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
		int j, cnt = 0;
		for(int i = 0; i < mConfigs.length; i++)
		{
			for(j = 0; j < i; j++)
				if(mConfigs[i].mName == mConfigs[j].mName)
					break;
			if(j >= i)
			{
				if(cnt < celt && rgbstr)
					rgbstr[cnt] = allocBSTR(mConfigs[i].mName);
				cnt++;
			}
		}
		if(pcActual)
			*pcActual = cnt;
		return S_OK;
	}


	override int GetPlatformNames(
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		int j, cnt = 0;
		for(int i = 0; i < mConfigs.length; i++)
		{
			for(j = 0; j < i; j++)
				if(mConfigs[i].mPlatform == mConfigs[j].mPlatform)
					break;
			if(j >= i)
			{
				if(cnt < celt)
					rgbstr[cnt] = allocBSTR(mConfigs[i].mPlatform);
				cnt++;
			}
		}
		if(pcActual)
			*pcActual = cnt;
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

		for(int i = 0; i < mConfigs.length; i++)
			if((plat == "" || plat == mConfigs[i].mPlatform) &&
			   (cfg == "" || mConfigs[i].mName == cfg))
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

		// copy configs for all platforms
		int cnt = mConfigs.length;
		for(int i = 0; i < cnt; i++)
			if(mConfigs[i].mName == strCloneCfgName)
			{
				Config config = newCom!Config(this, strCfgName, mConfigs[i].mPlatform, mConfigs[i].mProjectOptions);
				mConfigs ~= addref(config);
			}

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameAdded(pszCfgName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file
		return S_OK;
	}

	override int DeleteCfgsOfCfgName(
		/* [in] */ in wchar* pszCfgName)
	{
		logCall("%s.DeleteCfgsOfCfgName(pszCfgName=%s)", this, _toLog(pszCfgName));

		string strCfgName = to_string(pszCfgName);
		int cnt = mConfigs.length;
		for(int i = 0; i < mConfigs.length; )
			if(mConfigs[i].mName == strCfgName)
				mConfigs = mConfigs[0..i] ~ mConfigs[i+1..$];
			else
				i++;
		if(cnt == mConfigs.length)
			return returnError(E_FAIL);

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameDeleted(pszCfgName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file
		return S_OK;
	}

	override int RenameCfgsOfCfgName(
		/* [in] */ in wchar* pszOldName,
		/* [in] */ in wchar* pszNewName)
	{
		mixin(LogCallMix2);

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

		foreach(c; mConfigs)
			if(c.mName == strOldName)
				c.mName = strNewName;

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameRenamed(pszOldName, pszNewName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file
		return S_OK;
	}

	override int AddCfgsOfPlatformName(
		/* [in] */ in wchar* pszPlatformName,
		/* [in] */ in wchar* pszClonePlatformName)
	{
		logCall("%s.AddCfgsOfPlatformName(pszPlatformName=%s,pszClonePlatformName=%s)", this, _toLog(pszPlatformName), _toLog(pszClonePlatformName));

		string strPlatformName = to_string(pszPlatformName);
		string strClonePlatformName = to_string(pszClonePlatformName);

		// Check if the CfgName already exists and that CloneCfgName exists
		Config clonecfg;
		foreach(c; mConfigs)
			if(c.mPlatform == strPlatformName)
				return returnError(E_FAIL);
			else if(c.mPlatform == strClonePlatformName)
				clonecfg = c;

		if(strClonePlatformName.length && !clonecfg)
			return returnError(E_FAIL);

		//if(!mProject.QueryEditProjectFile())
		//	return returnError(E_ABORT);

		int cnt = mConfigs.length;
		for(int i = 0; i < cnt; i++)
			if(mConfigs[i].mPlatform == strClonePlatformName)
			{
				Config config = newCom!Config(this, mConfigs[i].mName, strPlatformName, mConfigs[i].mProjectOptions);
				mConfigs ~= addref(config);
			}

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnPlatformNameAdded(pszPlatformName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file
		return S_OK;
	}

	override int DeleteCfgsOfPlatformName(
		/* [in] */ in wchar* pszPlatformName)
	{
		logCall("%s.DeleteCfgsOfPlatformName(pszPlatformName=%s)", this, _toLog(pszPlatformName));

		string strPlatformName = to_string(pszPlatformName);
		int cnt = mConfigs.length;
		for(int i = 0; i < mConfigs.length; )
			if(mConfigs[i].mPlatform == strPlatformName)
				mConfigs = mConfigs[0..i] ~ mConfigs[i+1..$];
			else
				i++;
		if(cnt == mConfigs.length)
			return returnError(E_FAIL);

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnPlatformNameDeleted(pszPlatformName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file
		return S_OK;
	}

	override int GetSupportedPlatformNames(
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		for(int cnt = 0; cnt < kPlatforms.length && cnt < celt && rgbstr; cnt++)
			rgbstr[cnt] = allocBSTR(kPlatforms[cnt]);
		if(pcActual)
			*pcActual = kPlatforms.length;
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
		case VSCFGPROPID_SupportsPlatformAdd:
		case VSCFGPROPID_SupportsPlatformDelete:
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

interface ConfigModifiedListener : IUnknown
{
	void OnConfigModified();
}

class Config :	DisposingComObject,
		IVsProjectCfg2,
		IVsDebuggableProjectCfg,
		IVsDebuggableProjectCfg2,
		IVsBuildableProjectCfg,
		IVsQueryDebuggableProjectCfg,
		IVsProfilableProjectCfg,
		ISpecifyPropertyPages
{
	static const GUID iid = { 0x402744c1, 0xe382, 0x4877, [ 0x9e, 0x38, 0x26, 0x9c, 0xb7, 0xa3, 0xb8, 0x9d ] };

	this(ConfigProvider provider, string name, string platform, ProjectOptions opts = null)
	{
		mProvider = provider;
		if (opts)
		{
			mProjectOptions = clone(opts);
			//mProjectOptions.setDebug(name == "Debug");
			mProjectOptions.setX64(platform == "x64");
		}
		else
			mProjectOptions = new ProjectOptions(name.startsWith("Debug"), platform == "x64");
		mBuilder = new CBuilderThread(this);
		version(hasOutputGroup)
			mOutputGroup = newCom!VsOutputGroup(this);
		mName = name;
		mPlatform = platform;
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

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
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
		if(queryInterface!(IVsDebuggableProjectCfg2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsBuildableProjectCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsQueryDebuggableProjectCfg) (this, riid, pvObject))
			return S_OK;
		version(hasProfilableConfig)
			if(queryInterface!(IVsProfilableProjectCfg) (this, riid, pvObject))
				return S_OK;

		return super.QueryInterface(riid, pvObject);
	}

	// ISpecifyPropertyPages
	override int GetPages( /* [out] */ CAUUID *pPages)
	{
		mixin(LogCallMix);
		CHierNode[] nodes;
		CFileNode file;
		CProjectNode proj;
		if(GetProject().GetSelectedNodes(nodes) == S_OK)
		{
			foreach(n; nodes)
			{
				if(!file)
					file = cast(CFileNode) n;
				if(!proj)
					proj = cast(CProjectNode) n;
			}
		}
		if (!proj)
			return PropertyPageFactory.GetFilePages(pPages);
		return PropertyPageFactory.GetProjectPages(pPages, false);
	}

	// IVsCfg
	override int get_DisplayName(BSTR *pbstrDisplayName)
	{
		logCall("%s.get_DisplayName(pbstrDisplayName=%s)", this, _toLog(pbstrDisplayName));

		*pbstrDisplayName = allocBSTR(getCfgName());
		return S_OK;
	}

	override int get_IsDebugOnly(BOOL *pfIsDebugOnly)
	{
		logCall("%s.get_IsDebugOnly(pfIsDebugOnly=%s)", this, _toLog(pfIsDebugOnly));

		*pfIsDebugOnly = mProjectOptions.release != 1;
		return S_OK;
	}

	override int get_IsReleaseOnly(BOOL *pfIsReleaseOnly)
	{
		logCall("%s.get_IsReleaseOnly(pfIsReleaseOnly=%s)", this, _toLog(pfIsReleaseOnly));

		*pfIsReleaseOnly = mProjectOptions.release == 1;
		return S_OK;
	}

	// IVsProjectCfg
	override int EnumOutputs(IVsEnumOutputs *ppIVsEnumOutputs)
	{
		mixin(LogCallMix);

		*ppIVsEnumOutputs = addref(newCom!DEnumOutputs(this, 0));
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
		*pbstrCanonicalName = allocBSTR(getName());
		return S_OK;
	}

	override int get_Platform( /* [out] */ GUID *pguidPlatform)
	{
		// The documentation says this is obsolete, so don't do anything.
		mixin(LogCallMix);
		*pguidPlatform = GUID(); //GUID_VS_PLATFORM_WIN32_X86;
		return returnError(E_NOTIMPL);
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
		debug(FULL_DBG) mixin(LogCallMix);
		return QueryInterface(iidCfg, ppCfg);
	}

	override int get_OutputGroups(
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ IVsOutputGroup *rgpcfg,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		version(hasOutputGroup)
		{
			if(celt >= 1)
				*rgpcfg = addref(mOutputGroup);
			if(pcActual)
				*pcActual = 1;
			return S_OK;
		}
		else
		{
			return returnError(E_NOTIMPL);
		}
	}

	override int OpenOutputGroup(
		/* [in] */ in wchar* szCanonicalName,
		/* [out] */ IVsOutputGroup *ppIVsOutputGroup)
	{
		mixin(LogCallMix);
		version(hasOutputGroup)
		{
			if(to_wstring(szCanonicalName) != to_wstring(VS_OUTPUTGROUP_CNAME_Built))
				return returnError(E_INVALIDARG);
			*ppIVsOutputGroup = addref(mOutputGroup);
			return S_OK;
		}
		else
		{
			return returnError(E_NOTIMPL);
		}
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

		if(!isAbsolute(prg))
			prg = GetProjectDir() ~ "\\" ~ prg;
		//prg = quoteFilename(prg);

		string workdir = mProjectOptions.replaceEnvironment(mProjectOptions.debugworkingdir, this);
		if(!isAbsolute(workdir))
			workdir = GetProjectDir() ~ "\\" ~ workdir;

		Package.GetGlobalOptions().addExecutionPath(workdir);

		string args = mProjectOptions.replaceEnvironment(mProjectOptions.debugarguments, this);
		if(DBGLAUNCH_NoDebug & grfLaunch)
		{
			if(mProjectOptions.pauseAfterRunning)
			{
				args = "/c " ~ quoteFilenameForCmd(prg) ~ " " ~ args ~ " & pause";
				prg = getCmdPath();
			}
			ShellExecuteW(null, null, toUTF16z(quoteFilename(prg)), toUTF16z(args), toUTF16z(workdir), SW_SHOWNORMAL);
			return(S_OK);
		}
		return _DebugLaunch(prg, workdir, args, mProjectOptions.debugEngine);
	}

	GUID getDebugEngineUID(int engine)
	{
		switch(engine)
		{
			case 1:
				return GUID_MaGoDebugger;
			case 2:
				return GUID_COMPlusNativeEng; // the mixed-mode debugger (works only on x86)
			default:
				return GUID_NativeOnlyEng; // works for x64
		}
	}

	HRESULT _DebugLaunch(string prg, string workdir, string args, int engine)
	{
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

			// if bstr-parameters not passed as BSTR parameters, VS2010 crashes on some systems
			//  not sure if they can be free'd afterwards...
			VsDebugTargetInfo dbgi;

			dbgi.cbSize = VsDebugTargetInfo.sizeof;
			dbgi.bstrRemoteMachine = null;
			string remote = mProjectOptions.replaceEnvironment(mProjectOptions.debugremote, this);

			if(remote.length == 0)
			{
				if(!std.file.exists(prg))
				{
					UtilMessageBox("The program to launch does not exist:\n" ~ prg, MB_OK, "Launch Debugger");
					return S_FALSE;
				}
				if(workdir.length && !isExistingDir(workdir))
				{
					UtilMessageBox("The working directory does not exist:\n" ~ workdir, MB_OK, "Launch Debugger");
					return S_FALSE;
				}
			}
			else
				dbgi.bstrRemoteMachine = allocBSTR(remote); // _toUTF16z(remote);

			dbgi.dlo = DLO_CreateProcess; // DLO_Custom;    // specifies how this process should be launched
			// clsidCustom is the clsid of the debug engine to use to launch the debugger
			dbgi.clsidCustom = getDebugEngineUID(engine);
			dbgi.bstrMdmRegisteredName = null; // used with DLO_AlreadyRunning. The name of the
			                                   // app as it is registered with the MDM.
			dbgi.bstrExe = allocBSTR(prg); // _toUTF16z(prg);
			dbgi.bstrCurDir = allocBSTR(workdir); // _toUTF16z(workdir);
			dbgi.bstrArg = allocBSTR(args); // _toUTF16z(args);
			dbgi.fSendStdoutToOutputWindow = mProjectOptions.debugStdOutToOutputWindow;

			hr = srpVsDebugger.LaunchDebugTargets(1, &dbgi);
			if (FAILED(hr))
			{
				string msg = format("cannot launch debugger on %s\nhr = %x", prg, hr);
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

	// IVsDebuggableProjectCfg2
	HRESULT OnBeforeDebugLaunch(in VSDBGLAUNCHFLAGS grfLaunch)
	{
		mixin(LogCallMix);
		return S_OK; // returnError(E_NOTIMPL);
	}

	// IVsQueryDebuggableProjectCfg
	HRESULT QueryDebugTargets(in VSDBGLAUNCHFLAGS grfLaunch, in ULONG cTargets,
							  VsDebugTargetInfo2 *dti, ULONG *pcActual)
	{
		if(cTargets > 0)
		{
			if(!dti)
				return E_INVALIDARG;
			string remote = mProjectOptions.replaceEnvironment(mProjectOptions.debugremote, this);
			string prg = mProjectOptions.replaceEnvironment(mProjectOptions.debugtarget, this);
			string args = mProjectOptions.replaceEnvironment(mProjectOptions.debugarguments, this);
			string workdir = mProjectOptions.replaceEnvironment(mProjectOptions.debugworkingdir, this);
			if(!isAbsolute(workdir))
				workdir = GetProjectDir() ~ "\\" ~ workdir;
			prg = makeFilenameAbsolute(prg, workdir);

			dti.cbSize = VsDebugTargetInfo2.sizeof;
			dti.dlo = DLO_CreateProcess;  // specifies how this process should be launched or attached
			dti.LaunchFlags = grfLaunch; // launch flags that were passed to IVsDebuggableProjectCfg::Launch
			dti.bstrRemoteMachine = remote.length ? allocBSTR(remote) : null;       // NULL for local machine, or remote machine name
			dti.bstrExe = allocBSTR(prg);
			dti.bstrArg = allocBSTR(args);
			dti.bstrCurDir = allocBSTR(workdir);
			dti.bstrEnv = null;
			dti.guidLaunchDebugEngine = getDebugEngineUID(mProjectOptions.debugEngine);
			dti.dwDebugEngineCount = 1;
			dti.pDebugEngines = cast(GUID*)CoTaskMemAlloc(GUID.sizeof);
			*(dti.pDebugEngines) = dti.guidLaunchDebugEngine;
			/+
			dti.guidPortSupplier;        // port supplier guid
			dti.bstrPortName;            // name of port from above supplier (NULL is fine)
			dti.bstrOptions;             // custom options, specific to each guidLaunchDebugEngine (NULL is recommended)
			dti.hStdInput;              // for file redirection
			dti.hStdOutput;             // for file redirection
			dti.hStdError;              // for file redirection
			dti.fSendToOutputWindow;     // if TRUE, stdout and stderr will be routed to the output window
			dti.dwProcessId;            // process id (DLO_AlreadyRunning)
			dti.pUnknown;           // interface pointer - usage depends on DEBUG_LAUNCH_OPERATION
			dti.guidProcessLanguage;     // Language of the hosting process. Used to preload EE's
			+/
		}
		if (pcActual)
			*pcActual = 1;
		return S_OK;
	}

	///////////////////////////////////////////////////////////////
	// IVsProfilableProjectCfg
	override HRESULT get_SuppressSignedAssemblyWarnings(/+[retval, out]+/VARIANT_BOOL* suppress)
	{
		mixin(LogCallMix);
		*suppress = FALSE;
		return S_OK;
	}
	override HRESULT get_LegacyWebSupportRequired(/+[retval, out]+/VARIANT_BOOL* required)
	{
		mixin(LogCallMix);
		*required = FALSE;
		return S_OK;
	}

	HRESULT GetSupportedProfilingTasks(/+[out]+/ SAFEARRAY *tasks)
	{
		mixin(LogCallMix);
		BSTR task = allocBSTR("ClassicCPUSampling");
		int index = 0;
		SafeArrayPutElement(tasks, &index, &task);
		return S_OK;
	}
	HRESULT BeforeLaunch(in BSTR profilingTask)
	{
		mixin(LogCallMix);
		return S_OK;
	}
	HRESULT BeforeTargetsLaunched()
	{
		mixin(LogCallMix);
		return S_OK;
	}
	HRESULT LaunchProfiler()
	{
		mixin(LogCallMix);
		version(hasProfilableConfig)
		{
			IVsProfilerLauncher launcher;
			GUID svcid = uuid_SVsProfilerLauncher;
			GUID clsid = uuid_IVsProfilerLauncher;
			if (IServiceProvider sp = visuald.dpackage.Package.s_instance.getServiceProvider())
				sp.QueryService(&svcid, &clsid, cast(void**)&launcher);
			if (!launcher)
				return E_NOTIMPL;

			auto infos = addref(newCom!EnumVsProfilerTargetInfos(this));
			scope(exit) release(launcher);
			scope(exit) release(infos);

			HRESULT hr = launcher.LaunchProfiler(infos);
			return hr;
		}
		else
			return returnError(E_NOTIMPL);
	}
	HRESULT QueryProfilerTargetInfoEnum(/+[out]+/ IEnumVsProfilerTargetInfos *targetsEnum)
	{
		version(hasProfilableConfig)
		{
			mixin(LogCallMix);
			*targetsEnum = addref(newCom!EnumVsProfilerTargetInfos(this));
			return S_OK;
		}
		else
			return returnError(E_NOTIMPL);
	}
	HRESULT AllBrowserTargetsFinished()
	{
		mixin(LogCallMix);
		return S_OK;
	}
	HRESULT ProfilerAnalysisFinished()
	{
		mixin(LogCallMix);
		return S_OK;
	}

	///////////////////////////////////////////////////////////////
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
			return mBuilder.Start(CBuilderThread.Operation.eRebuild, pIVsOutputWindowPane);
		return mBuilder.Start(CBuilderThread.Operation.eBuild, pIVsOutputWindowPane);
	}

	override int StartClean(
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);

		return mBuilder.Start(CBuilderThread.Operation.eClean, pIVsOutputWindowPane);
	}

	override int StartUpToDateCheck(
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);

		HRESULT rc = mBuilder.Start(CBuilderThread.Operation.eCheckUpToDate, pIVsOutputWindowPane);
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
		debug(FULL_DBG) mixin(LogCallMix);

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
	void AddModifiedListener(ConfigModifiedListener listener)
	{
		mModifiedListener.addunique(listener);
	}

	void RemoveModifiedListener(ConfigModifiedListener listener)
	{
		mModifiedListener.remove(listener);
	}

	//////////////////////////////////////////////////////////////////////////////
	void SetDirty()
	{
		mProvider.mProject.GetProjectNode().SetProjectFileDirty(true);

		foreach(listener; mModifiedListener)
			listener.OnConfigModified();
	}

	CProjectNode GetProjectNode() { return mProvider.mProject.GetProjectNode(); }
	string GetProjectPath() { return mProvider.mProject.GetFilename(); }
	string GetProjectDir() { return dirName(mProvider.mProject.GetFilename()); }
	string GetProjectName() { return mProvider.mProject.GetProjectNode().GetName(); }
	Project GetProject() { return mProvider.mProject; }

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

	string GetLinkDependenciesPath()
	{
		string dep = GetDependenciesPath();
		assert(dep[$-4..$] == ".dep");
		return dep[0..$-4] ~ ".lnkdep";
	}

	string GetCppCompiler()
	{
		switch(mProjectOptions.compiler)
		{
			default:
			case Compiler.DMD: return mProjectOptions.mscoff || mProjectOptions.isX86_64 ? "cl" : "dmc";
			case Compiler.GDC: return "gcc";
			case Compiler.LDC: return mProjectOptions.isLDCforMinGW() ? "clang" : "cl";
		}
	}

	bool hasLinkDependencies()
	{
		return mProjectOptions.callLinkerDirectly() && Package.GetGlobalOptions().optlinkDeps;
	}

	string GetCommandLinePath(bool linkStep)
	{
		string exe = mProjectOptions.getCommandLinePath(linkStep);
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
		if(tool == "Custom" || tool == kToolResourceCompiler || tool == kToolCpp)
		{
			string outfile = GetOutputFile(file);
			string dep = file.GetDependencies(getCfgName());
			dep = mProjectOptions.replaceEnvironment(dep, this, file.GetFilename(), outfile);
			string[] deps = tokenizeArgs(dep);
			deps ~= file.GetFilename();
			string workdir = GetProjectDir();
			foreach(ref string s; deps)
				s = makeFilenameAbsolute(unquoteArgument(s), workdir);
			return deps;
		}
		if(tool == "DMDsingle")
		{
			string outfile = GetOutputFile(file);
			string depfile = outfile ~ ".dep";
			depfile = mProjectOptions.replaceEnvironment(depfile, this, file.GetFilename(), outfile);

			string workdir = GetProjectDir();
			string deppath = makeFilenameAbsolute(depfile, workdir);

			string[] files;
			bool depok = false;
			if(std.file.exists(deppath))
				depok = getFilenamesFromDepFile(deppath, files);
			if(!depok)
				files ~= deppath; // force update without if dependency file does not exist or is invalid

			files ~= file.GetFilename();
			files ~= getDDocFileList();
			makeFilenamesAbsolute(files, workdir);
			return files;
		}
		return null;
	}

	string getCustomCommandFile(string outfile)
	{
		string workdir = GetProjectDir();
		string cmdfile = std.path.buildPath(GetIntermediateDir(), baseName(outfile) ~ "." ~ kCmdLogFileExtension);
		cmdfile = makeFilenameAbsolute(cmdfile, workdir);
		return cmdfile;
	}

	bool isUptodate(CFileNode file, string* preason)
	{
		string fcmd = GetCompileCommand(file);
		if(fcmd.length == 0)
			return true;

		string outfile = GetOutputFile(file);
		outfile = mProjectOptions.replaceEnvironment(outfile, this, file.GetFilename(), outfile);

		string workdir = GetProjectDir();
		string cmdfile = getCustomCommandFile(outfile);

		if(!compareCommandFile(cmdfile, fcmd))
		{
			if(preason)
				*preason = "command line has changed";
			return false;
		}

		string[] deps = GetDependencies(file);

		outfile = makeFilenameAbsolute(outfile, workdir);
		string oldestFile, newestFile;
		long targettm = getOldestFileTime( [ outfile ], oldestFile );
		long sourcetm = getNewestFileTime(deps, newestFile);

		if(targettm > sourcetm)
			return true;
		if(file.GetUptodateWithSameTime(getCfgName()) && targettm == sourcetm)
			return true;
		if(preason)
			*preason = newestFile ~ " is newer";
		return false;
	}

	static bool IsResource(CFileNode file)
	{
		string tool = file.GetTool(null);
		if(tool == "")
			if(toLower(extension(file.GetFilename())) == ".rc")
				return true;
		return tool == kToolResourceCompiler;
	}

	static string GetStaticCompileTool(CFileNode file, string cfgname)
	{
		string tool = file.GetTool(cfgname);
		if(tool == "")
		{
			string fname = file.GetFilename();
			string ext = toLower(extension(fname));
			if(isIn(ext, ".d", ".ddoc", ".def", ".lib", ".obj", ".o", ".res"))
				tool = "DMD";
			else if(ext == ".rc")
				tool = kToolResourceCompiler;
			else if(isIn(ext, ".c", ".cpp", ".cxx", ".cc"))
				tool = kToolCpp;
		}
		return tool;
	}

	string GetCompileTool(CFileNode file)
	{
		string tool = file.GetTool(getCfgName());
		if(tool == "")
		{
			string fname = file.GetFilename();
			string ext = toLower(extension(fname));
			if(ext == ".d" && mProjectOptions.compilationModel == ProjectOptions.kSingleFileCompilation)
				tool = "DMDsingle";
			else if(isIn(ext, ".d", ".ddoc", ".def", ".lib", ".obj", ".o", ".res"))
				tool = "DMD";
			else if(ext == ".rc")
				tool = kToolResourceCompiler;
			else if(isIn(ext, ".c", ".cpp", ".cxx", ".cc"))
				tool = kToolCpp;
		}
		return tool;
	}

	string GetOutputFile(CFileNode file, string tool = null)
	{
		if(tool.empty)
			tool = GetCompileTool(file);
		string fname;
		if(tool == "DMD")
			return file.GetFilename();
		if(tool == "DMDsingle")
			fname = mProjectOptions.objdir ~ "\\" ~ safeFilename(stripExtension(file.GetFilename())) ~ "." ~ mProjectOptions.objectFileExtension();
		if(tool == "RDMD")
			fname = mProjectOptions.outdir ~ "\\" ~ safeFilename(stripExtension(file.GetFilename())) ~ ".exe";
		if(tool == kToolResourceCompiler)
			fname = mProjectOptions.objdir ~ "\\" ~ safeFilename(stripExtension(file.GetFilename()), "_") ~ ".res";
		if(tool == kToolCpp)
			fname = mProjectOptions.objdir ~ "\\" ~ safeFilename(stripExtension(file.GetFilename()), "_") ~ ".obj";
		if(tool == "Custom")
			fname = file.GetOutFile(getCfgName());
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

	string GetBuildLogFile()
	{
		return expandedAbsoluteFilename("$(INTDIR)\\$(SAFEPROJECTNAME).buildlog.html");
	}

	string[] GetBuildFiles()
	{
		string workdir = normalizeDir(GetProjectDir());
		string outdir = normalizeDir(makeFilenameAbsolute(GetOutDir(), workdir));
		string intermediatedir = normalizeDir(makeFilenameAbsolute(GetIntermediateDir(), workdir));

		string target = makeFilenameAbsolute(GetTargetPath(), workdir);
		string cmdfile = makeFilenameAbsolute(GetCommandLinePath(false), workdir);
		string lnkfile = makeFilenameAbsolute(GetCommandLinePath(true), workdir);

		string[] files;
		files ~= target;
		files ~= cmdfile;
		files ~= cmdfile ~ ".rsp";
		files ~= lnkfile;
		files ~= lnkfile ~ ".rsp";
		files ~= makeFilenameAbsolute(GetDependenciesPath(), workdir);
		files ~= makeFilenameAbsolute(GetLinkDependenciesPath(), workdir);

		if(mProjectOptions.usesCv2pdb())
			files ~= expandedAbsoluteFilename(mProjectOptions.getCvTargetPath());

		files ~= expandedAbsoluteFilename(mProjectOptions.pdbfile);
		files ~= expandedAbsoluteFilename(mProjectOptions.mapfile);

		string impfile = expandedAbsoluteFilename(mProjectOptions.impfile);
		files ~= impfile;
		files ~= stripExtension(impfile) ~ ".exp"; // export file

		files ~= GetBuildLogFile();

		if(mProjectOptions.createImplib)
			files ~= setExtension(target, "lib");

		if(mProjectOptions.doDocComments)
		{
			if(mProjectOptions.docdir.length)
				files ~= expandedAbsoluteFilename(normalizeDir(mProjectOptions.docdir)) ~ "*.html";
			if(mProjectOptions.docname.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.docname);
			if(mProjectOptions.modules_ddoc.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.modules_ddoc);
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

		string[] toclean = tokenizeArgs(mProjectOptions.filesToClean);
		foreach(s; toclean)
		{
			string uqs = unquoteArgument(s);
			files ~= outdir ~ uqs;
			if(outdir != intermediatedir)
				files ~= intermediatedir ~ uqs;
		}
		searchNode(mProvider.mProject.GetRootNode(),
			delegate (CHierNode n) {
				if(CFileNode file = cast(CFileNode) n)
				{
					string outname = GetOutputFile(file);
					if (outname.length && outname != file.GetFilename())
					{
						files ~= makeFilenameAbsolute(outname, workdir);
						string cmdfile = getCustomCommandFile(outname);
					}
				}
				return false;
			});

		return files;
	}

	string GetCompileCommand(CFileNode file, bool syntaxOnly = false, string tool = null, string addopt = null)
	{
		if(tool.empty)
			tool = GetCompileTool(file);
		string cmd;
		string outfile = GetOutputFile(file, tool);
		if(tool == kToolResourceCompiler)
		{
			cmd = "rc /fo" ~ quoteFilename(outfile);
			string include = Package.GetGlobalOptions().IncSearchPath;
			if(include.length)
			{
				string[] incs = tokenizeArgs(include);
				foreach(string inc; incs)
					cmd ~= " /I" ~ quoteFilename(inc);
				cmd = mProjectOptions.replaceEnvironment(cmd, this, outfile);
			}
			string addOpts = file.GetAdditionalOptions(getCfgName());
			if(addOpts.length)
				cmd ~= " " ~ addOpts;
			cmd ~= " " ~ quoteFilename(file.GetFilename());
		}
		if(tool == kToolCpp)
		{
			cmd = mProjectOptions.getCppCommandLine(outfile, true);
			string addOpts = file.GetAdditionalOptions(getCfgName());
			if(addOpts.length)
				cmd ~= " " ~ addOpts;
			cmd ~= " " ~ quoteFilename(file.GetFilename());
		}
		if(tool == "Custom")
		{
			cmd = file.GetCustomCmd(getCfgName());
		}
		if(tool == "DMDsingle")
		{
			string depfile = syntaxOnly ? null : GetOutputFile(file, tool) ~ ".dep";
			cmd = "echo Compiling " ~ file.GetFilename() ~ "...\n";
			cmd ~= mProjectOptions.buildCommandLine(this, true, false, depfile, syntaxOnly);
			if(syntaxOnly && mProjectOptions.compiler == Compiler.GDC)
				cmd ~= " -c -fsyntax-only";
			else if(syntaxOnly)
				cmd ~= " -c -o-";
			else
				cmd ~= " -c " ~ mProjectOptions.getOutputFileOption(outfile);
			if(mProjectOptions.additionalOptions.length)
				cmd ~= " " ~ mProjectOptions.additionalOptions.replace("\n", " ");
			cmd ~= " " ~ quoteFilename(file.GetFilename());
			foreach(ddoc; getDDocFileList())
				cmd ~= " " ~ ddoc;
		}
		if(tool == "RDMD" || tool == "RDMDeval")
		{
			// temporarily switch to "rdmd"
			ProjectOptions opts = clone(mProjectOptions);
			opts.compiler = Compiler.DMD;
			opts.program = "rdmd";
			opts.otherDMD = true;
			opts.mapverbosity = 2; // no map option
			opts.otherDMD = true;
			opts.doXGeneration = false;
			opts.doHdrGeneration = false;
			opts.doDocComments = false;
			opts.lib = OutputType.Executable;
			//opts.runCv2pdb = false;
			opts.exefile = "$(OutDir)\\" ~ baseName(stripExtension(outfile)) ~ ".exe";

			bool eval = tool == "RDMDeval";
			if (eval)
				cmd = "echo Compiling selection...\n";
			else
				cmd = "echo Compiling " ~ file.GetFilename() ~ "...\n";
			// add environment in case sc.ini was not patched to a specific VS version
			cmd ~= getMSVCEnvironmentCommands();
			cmd ~= opts.buildCommandLine(this, true, !eval && !syntaxOnly, null, syntaxOnly);
			if(syntaxOnly && !eval)
				cmd ~= " --build-only";
			cmd ~= addopt;
			if (!eval)
				cmd ~= " " ~ quoteFilename(file.GetFilename());
			addopt = ""; // must be before filename for rdmd
			if (!syntaxOnly && !eval)
			{
				string cv2pdb = opts.appendCv2pdb();
				if (cv2pdb.length)
					cmd ~= "\nif %errorlevel% neq 0 goto reportError\n" ~ opts.appendCv2pdb();
			}
		}
		if(cmd.length)
		{
			cmd = getEnvironmentChanges() ~ cmd ~ addopt ~ "\n:reportError\n";
			if(syntaxOnly)
				cmd ~= "if %errorlevel% neq 0 echo Compiling " ~ file.GetFilename() ~ " failed!\n";
			else
				cmd ~= "if %errorlevel% neq 0 echo Building " ~ outfile ~ " failed!\n";
			cmd = mProjectOptions.replaceEnvironment(cmd, this, file.GetFilename(), outfile);
		}
		return cmd;
	}

	string GetDisasmCommand(string objfile, string outfile)
	{
		bool x64 = mProjectOptions.isX86_64;
		bool mscoff = mProjectOptions.compiler == Compiler.DMD && mProjectOptions.mscoff;
		GlobalOptions globOpt = Package.GetGlobalOptions();
		string cmd = x64    ? mProjectOptions.compilerDirectories.DisasmCommand64 :
		             mscoff ? mProjectOptions.compilerDirectories.DisasmCommand32coff : mProjectOptions.compilerDirectories.DisasmCommand;
		if(globOpt.demangleError)
		{
			string mangledfile = outfile ~ ".mangled";
			cmd = mProjectOptions.replaceEnvironment(cmd, this, objfile, mangledfile);
			cmd ~= "\nif errorlevel 0 \"" ~ Package.GetGlobalOptions().VisualDInstallDir ~ "dcxxfilt.exe\" < " ~ quoteFilename(mangledfile) ~ " > " ~ quoteFilename(outfile);
		}
		else
			cmd = mProjectOptions.replaceEnvironment(cmd, this, objfile, outfile);
		return cmd;
	}

	string getEnvironmentChanges()
	{
		string cmd;
		bool x64 = mProjectOptions.isX86_64;
		bool mscoff = mProjectOptions.compiler == Compiler.DMD && mProjectOptions.mscoff;
		GlobalOptions globOpt = Package.GetGlobalOptions();
		string exeSearchPath = x64    ? mProjectOptions.compilerDirectories.ExeSearchPath64 :
		                       mscoff ? mProjectOptions.compilerDirectories.ExeSearchPath32coff : mProjectOptions.compilerDirectories.ExeSearchPath;
		if(exeSearchPath.length)
			cmd ~= "set PATH=" ~ replaceCrLfSemi(exeSearchPath) ~ ";%PATH%\n";

		string libSearchPath = x64    ? mProjectOptions.compilerDirectories.LibSearchPath64 :
		                       mscoff ? mProjectOptions.compilerDirectories.LibSearchPath32coff : mProjectOptions.compilerDirectories.LibSearchPath;
		bool hasGlobalPath = mProjectOptions.useStdLibPath && libSearchPath.length;
		if(hasGlobalPath || mProjectOptions.libpaths.length)
		{
			// obsolete?
			string lpath;
			if(hasGlobalPath)
				lpath = replaceCrLfSemi(libSearchPath);
			if(mProjectOptions.libpaths.length && !_endsWith(lpath, ";"))
				lpath ~= ";";
			lpath ~= mProjectOptions.libpaths;

			if(mProjectOptions.compiler == Compiler.DMD)
				cmd ~= "set DMD_LIB=" ~ lpath ~ "\n";
			else if(mProjectOptions.compiler == Compiler.LDC)
				cmd ~= "set LIB=" ~ lpath ~ "\n";
		}
		if(mProjectOptions.useMSVCRT())
			cmd ~= getMSVCEnvironmentCommands;

		return cmd;
	}

	string getMSVCEnvironmentCommands()
	{
		GlobalOptions globOpt = Package.GetGlobalOptions();
		string cmd;
		if(globOpt.VCInstallDir.length)
			cmd ~= "set VCINSTALLDIR=" ~ globOpt.VCInstallDir ~ "\n";
		if(globOpt.VCToolsInstallDir.length)
			cmd ~= "set VCTOOLSINSTALLDIR=" ~ globOpt.VCToolsInstallDir ~ "\n";
		if(globOpt.VSInstallDir.length)
			cmd ~= "set VSINSTALLDIR=" ~ globOpt.VSInstallDir ~ "\n";
		if(globOpt.WindowsSdkDir.length)
			cmd ~= "set WindowsSdkDir=" ~ globOpt.WindowsSdkDir ~ "\n";
		if(globOpt.WindowsSdkVersion.length)
			cmd ~= "set WindowsSdkVersion=" ~ globOpt.WindowsSdkVersion ~ "\n";
		if(globOpt.UCRTSdkDir.length)
			cmd ~= "set UniversalCRTSdkDir=" ~ globOpt.UCRTSdkDir ~ "\n";
		if(globOpt.UCRTVersion.length)
			cmd ~= "set UCRTVersion=" ~ globOpt.UCRTVersion ~ "\n";
		return cmd;
	}

	string getModuleName(string fname)
	{
		string ext = toLower(extension(fname));
		if(ext != ".d" && ext != ".di")
			return "";

		string modname = getModuleDeclarationName(fname);
		if(modname.length > 0)
			return modname;
		return stripExtension(baseName(fname));
	}

	string getModulesDDocCommandLine(string[] files, ref string modules_ddoc)
	{
		if(!mProjectOptions.doDocComments)
			return "";
		string mod_cmd;
		modules_ddoc = strip(mProjectOptions.modules_ddoc);
		if(modules_ddoc.length > 0)
		{
			modules_ddoc = quoteFilename(modules_ddoc);
			mod_cmd = "echo MODULES = >" ~ modules_ddoc ~ "\n";
			string workdir = GetProjectDir();
			for(int i = 0; i < files.length; i++)
			{
				string fname = makeFilenameAbsolute(files[i], workdir);
				string mod = getModuleName(fname);
				if(mod.length > 0)
				{
					if(indexOf(mod, '.') < 0)
						mod = "." ~ mod;
					mod_cmd ~= "echo     $$(MODULE " ~ mod ~ ") >>" ~ modules_ddoc ~ "\n";
				}
			}
		}
		return mod_cmd;
	}

	string getCommandFileList(string[] files, string responsefile, ref string precmd)
	{
		if(mProjectOptions.compiler == Compiler.GDC)
			foreach(ref f; files)
				f = replace(f, "\\", "/");

		files = files.dup;
		quoteFilenames(files);
		string fcmd = std.string.join(files, " ");
		if(fcmd.length > 100)
		{
			precmd ~= "\n";
			precmd ~= "echo " ~ files[0] ~ " >" ~ quoteFilename(responsefile) ~ "\n";
			for(int i = 1; i < files.length; i++)
				precmd ~= "echo " ~ files[i] ~ " >>" ~ quoteFilename(responsefile) ~ "\n";
			precmd ~= "\n";
			fcmd = " @" ~ quoteFilename(responsefile);
		}
		else if (fcmd.length)
			fcmd = " " ~ fcmd;

		if(mProjectOptions.compiler == Compiler.GDC && mProjectOptions.libfiles.length)
			fcmd ~= " " ~ replace(mProjectOptions.libfiles, "\\", "/");

		return fcmd;
	}

	string[] getObjectFileList(string[] dfiles)
	{
		string[] files = dfiles.dup;
		string[] remove;
		bool singleObj = mProjectOptions.isCombinedBuild();
		string targetObj;
		foreach(ref f; files)
			if(f.endsWith(".d") || f.endsWith(".D"))
			{
				if(singleObj)
				{
					if(targetObj.length)
						remove ~= f;
					else
					{
						targetObj = "$(IntDir)\\$(ProjectName)." ~ mProjectOptions.objectFileExtension();
						f = targetObj;
					}
				}
				else
				{
					string fname = stripExtension(f);
					if(!mProjectOptions.preservePaths)
						fname = baseName(fname);
					fname ~= "." ~ mProjectOptions.objectFileExtension();
					if(mProjectOptions.compiler.isIn(Compiler.DMD, Compiler.LDC) && !isAbsolute(fname))
						f = mProjectOptions.objdir ~ "\\" ~ fname;
					else
						f = fname;
				}
			}

		foreach(r; remove)
			files.remove(r);
		return files;
	}

	string getLinkFileList(string[] dfiles, ref string precmd)
	{
		string[] files = getObjectFileList(dfiles);
		string responsefile = GetCommandLinePath(true) ~ ".rsp";
		return getCommandFileList(files, responsefile, precmd);
	}

	string[] getSourceFileList()
	{
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(),
			delegate (CHierNode n) {
				if(CFileNode file = cast(CFileNode) n)
					files ~= file.GetFilename();
				return false;
			});
		return files;
	}

	string[] getDDocFileList()
	{
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(),
			delegate (CHierNode n) {
				if(CFileNode file = cast(CFileNode) n)
				{
					string fname = file.GetFilename();
					if(extension(fname) == ".ddoc")
						files ~= fname;
				}
				return false;
			});
		return files;
	}

	string[] getInputFileList()
	{
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(),
			delegate (CHierNode n) {
				if(CFileNode file = cast(CFileNode) n)
				{
					string fname = GetOutputFile(file);
					if(fname.length)
						if(file.GetTool(getCfgName()) != "Custom" || file.GetLinkOutput(getCfgName()))
							files ~= fname;
				}
				return false;
			});

		string[] libs = getLibsFromDependentProjects();
		foreach(lib; libs)
		{
			// dmd also understands ".json", ".map" and ".exe", but these are shortcuts for output files
			string ext = toLower(extension(lib));
			if(ext.isIn(".d", ".di", ".o", ".obj", ".lib", ".a", ".ddoc", ".res", ".def", ".dd", ".htm", ".html", ".xhtml"))
				files ~= lib;
		}
		return files;
	}

	string[] filterTroublesomeOptions(string[] cmds)
	{
		// filter out options that can cause unexpected failures due to file accesses
		size_t j = 0;
		for (size_t i = 0; i < cmds.length; i++)
		{
			if (cmds[i] == "-lib")
				continue;
			if (cmds[i] == "-vcg-ast")
				continue;
			if (cmds[i] == "-run")
				break;
			if (cmds[i].startsWith("-X")) // json
				continue;
			if (cmds[i].startsWith("-H")) // hdr
				continue;
			if (cmds[i].startsWith("-D")) // doc
				continue;
			if (cmds[i].startsWith("-deps"))
				continue;
			cmds[j++] = cmds[i];
		}
		return cmds[0..j];
	}

	string getCompilerVersionIDs(string cmd = null)
	{
		ProjectOptions opts = GetProjectOptions();
		if (!cmd)
		{
			cmd = opts.buildCommandLine(this, true, false, null, true);
			if (opts.additionalOptions.length)
				cmd ~= " " ~ opts.additionalOptions;
		}
		cmd ~= " -v -o- dummy.obj";

		__gshared string[string] cachedVersions;
		synchronized
		{
			if (cmd.startsWith("dmd "))
				cmd = quoteFilename(Package.GetGlobalOptions().DMD.getCompilerPath()) ~ cmd[3..$];
			else if (cmd.startsWith("ldc2 "))
				cmd = quoteFilename(Package.GetGlobalOptions().LDC.getCompilerPath()) ~ cmd[4..$];
			else if (cmd.startsWith("gdc "))
				cmd = quoteFilename(Package.GetGlobalOptions().GDC.getCompilerPath()) ~ cmd[3..$];

			string key = cmd;
			if (auto p = key in cachedVersions)
				return *p;

			string versions = opts.versionids;
			try
			{
				auto cmds = tokenizeArgs(cmd);
				cmds = filterTroublesomeOptions(cmds);
				auto res = execute(cmds, null, ExecConfig.suppressConsole);
				if (res.status == 0)
				{
					auto lines = res.output.splitLines;
					foreach(line; lines)
						if (line.startsWith("predefs"))
							versions = line[7..$];
				}
			}
			catch(Exception)
			{
			}
			cachedVersions[key] = versions;
			return versions;
		}
	}

	string GetPhobosPath()
	{
		string libpath = normalizeDir(GetIntermediateDir());
		string libfile = "privatephobos.lib";
		return libpath ~ libfile;
	}

	string GetPhobosCommandLine()
	{
		string libpath = normalizeDir(GetIntermediateDir());

		bool x64 = mProjectOptions.isX86_64;
		bool mscoff = mProjectOptions.compiler == Compiler.DMD && mProjectOptions.mscoff;
		string model = "32";
		if(x64)
			model = "64";
		else if (mscoff)
			model = "32mscoff";

		string libfile = "privatephobos.lib";
		string lib = libpath ~ libfile;

		string cmdfile = libpath ~ "buildphobos.bat";
		string dmddir = Package.GetGlobalOptions().findDmdBinDir();
		string dmdpath = dmddir ~ "dmd.exe";
		string installDir = normalizeDir(Package.GetGlobalOptions().DMD.InstallDir);

		if(!std.file.exists(dmdpath))
			return "echo dmd.exe not found in DMDInstallDir=" ~ installDir ~ " or through PATH\nexit /B 1";

		string druntimePath = "src\\druntime\\src\\";
		if(!std.file.exists(installDir ~ druntimePath ~ "object_.d") &&
		   !std.file.exists(installDir ~ druntimePath ~ "object.d")) // dmd >=2.068 no longer has object_.d
			druntimePath = "druntime\\src\\";
		if(!std.file.exists(installDir ~ druntimePath ~ "object_.d") &&
		   !std.file.exists(installDir ~ druntimePath ~ "object.d"))
			return "echo druntime source not found in DMDInstallDir=" ~ installDir ~ "\nexit /B 1";

		string phobosPath = "src\\phobos\\";
		if(!std.file.exists(installDir ~ phobosPath ~ "std"))
			phobosPath = "phobos\\";
		if(!std.file.exists(installDir ~ phobosPath ~ "std"))
			return "echo phobos source not found in DMDInstallDir=" ~ installDir ~ "\nexit /B 1";

		string cmdline = "@echo off\n";
		cmdline ~= "echo Building " ~ lib ~ "\n";
		cmdline ~= getEnvironmentChanges();

		string opts = " -lib -d " ~ mProjectOptions.dmdCommonCompileOptions();

		// collect C files
		string[] cfiles;
		if (mscoff || x64) // msvc*.c
			cfiles ~= findDRuntimeFiles(installDir, druntimePath ~ "rt", true, true, true);
		cfiles ~= findDRuntimeFiles(installDir, druntimePath ~ "core", true, true, true);
		cfiles ~= findDRuntimeFiles(installDir, phobosPath ~ "etc\\c", true, true, true);
		if (cfiles.length)
		{
			foreach(i, ref file; cfiles)
			{
				file = installDir ~ file;
				string outfile = libpath ~ "phobos-" ~ baseName(file) ~ ".obj";
				string cccmd = mProjectOptions.getCppCommandLine(outfile, i == 0);
				cmdline ~= cccmd ~ " -DNO_snprintf " ~ file ~ "\n";
				cmdline ~= "if %errorlevel% neq 0 exit /B %ERRORLEVEL%\n\n";
				file = outfile;
			}
		}

		// collect druntime D files
		string[] files;
		if(std.file.exists(installDir ~ druntimePath ~ "object_.d"))
			files ~= druntimePath ~ "object_.d";
		else
			files ~= druntimePath ~ "object.d"; // dmd >=2.068 no longer has object.di
		files ~= findDRuntimeFiles(installDir, druntimePath ~ "rt",   true, false, true);
		files ~= findDRuntimeFiles(installDir, druntimePath ~ "core", true, false, true);
		files ~= findDRuntimeFiles(installDir, druntimePath ~ "gc",   true, false, true);
		foreach(ref file; files)
			file = installDir ~ file;
		files ~= cfiles;
		if(model == "32")
			files ~= installDir ~ druntimePath ~ "rt\\minit.obj";

		string dmd;
		if(mProjectOptions.otherDMD && mProjectOptions.program.length)
			dmd = quoteNormalizeFilename(mProjectOptions.program);
		else
			dmd = "dmd";

		static string buildFiles(string dmd, string outlib, string[] files)
		{
			string rspfile = outlib ~ ".rsp";
			string qrspfile = quoteFilename(rspfile);
			string cmdline = "echo. >" ~ qrspfile ~ "\n";
			foreach(file; files)
				cmdline ~= "echo " ~ quoteFilename(file) ~ " >>" ~ qrspfile ~ "\n";
			cmdline ~= dmd ~ " -of" ~ quoteFilename(outlib) ~ " @" ~ qrspfile ~ "\n\n";
			return cmdline;
		}

		// because of inconsistent object.di and object_.d in dmd <2.067 we have to build
		//  druntime and phobos seperately

		string druntimelib = libpath ~ "privatedruntime.lib";
		cmdline ~= buildFiles(dmd ~ opts, druntimelib, files);
		cmdline ~= "if %errorlevel% neq 0 exit /B %ERRORLEVEL%\n\n";

		// collect phobos D files
		files = null;
		files ~= findDRuntimeFiles(installDir, phobosPath ~ "std",    true, false, true);
		files ~= findDRuntimeFiles(installDir, phobosPath ~ "etc\\c", true, false, true);
		foreach(ref file; files)
			file = installDir ~ file;

		cmdline ~= buildFiles(dmd ~ opts ~ " " ~ quoteFilename(druntimelib), lib, files);

		cmdline = mProjectOptions.replaceEnvironment(cmdline, this, null, lib);

		return cmdline;
	}

	bool isPhobosUptodate(string* preason)
	{
		string workdir = GetProjectDir();
		string outfile = GetPhobosPath();
		string lib = makeFilenameAbsolute(outfile, workdir);
		if (!std.file.exists(lib))
		{
			if(preason)
				*preason = "does not exist";
			return false;
		}
		string cmd = GetPhobosCommandLine();
		if(cmd.length == 0)
			return true;

		string cmdfile = makeFilenameAbsolute(outfile ~ "." ~ kCmdLogFileExtension, workdir);
		if(!compareCommandFile(cmdfile, cmd))
		{
			if(preason)
				*preason = "command line has changed";
			return false;
		}

		// no further dependency checks
		return true;
	}

	string getDubCommandLine(string command, bool rebuild)
	{
		bool x64       = mProjectOptions.isX86_64;
		bool mscoff    = mProjectOptions.compiler == Compiler.DMD && (x64 || mProjectOptions.mscoff);
		string workdir = normalizeDir(GetProjectDir());
		auto globOpts  = Package.GetGlobalOptions();
		auto dubfile   = mProvider.mProject.findDubConfigFile();
		string root    = workdir;
		if (dubfile)
			root = makeFilenameAbsolute(dubfile.GetFilename(), workdir).dirName;

		string dubpath = globOpts.dubPath;
		if (!std.file.exists(dubpath))
			dubpath = normalizeDir(globOpts.DMD.InstallDir) ~ "windows\\bin\\dub.exe";

		string dubcmd;
		if (root != workdir)
			dubcmd ~= "cd /D " ~ quoteFilename(root) ~ "\n";

		if (command == "build")
		{
			dubcmd ~= "\"$(VisualDInstallDir)pipedmd.exe\" "
				~ (globOpts.demangleError ? null : "-nodemangle ")
				~ (mProjectOptions.usesMSLink() ? "-msmode " : null)
				~ (usePipedmdForDeps ? "-deps " ~ quoteFilename(GetDependenciesPath()) ~ " " : null)
				~ quoteFilename(dubpath) ~ " build";
		}
		else
		{
			dubcmd ~= quoteFilename(dubpath) ~ " " ~ command;
		}
		if (command == "generate")
			dubcmd ~= " visuald";

		if (globOpts.dubOptions.length)
			dubcmd ~= " " ~ globOpts.dubOptions;

		if (command == "build" || command == "generate")
		{
			switch (mProjectOptions.compiler)
			{
				default:
				case Compiler.DMD:
					dubcmd ~= " --compiler=dmd";
					break;
				case Compiler.LDC:
					dubcmd ~= " --compiler=ldc";
					break;
				case Compiler.GDC:
					dubcmd ~= " --compiler=gdc";
					break;
			}
			if (x64)
				dubcmd ~= " --arch=x86_64";
			else if (mscoff)
				dubcmd ~= " --arch=x86_mscoff";
			else
				dubcmd ~= " --arch=x86";

			dubcmd ~= " --build=" ~ toLower(mName);
			if (rebuild)
				dubcmd ~= " --force";
		}

		return dubcmd;
	}

	string getCommandLine(bool compile, bool link, bool rebuild)
	{
		assert(compile || link);

		bool doLink       = mProjectOptions.compilationModel != ProjectOptions.kSeparateCompileOnly;
		bool separateLink = mProjectOptions.doSeparateLink();
		bool x64          = mProjectOptions.isX86_64;
		bool mscoff       = mProjectOptions.compiler == Compiler.DMD && (x64 || mProjectOptions.mscoff);
		string workdir    = normalizeDir(GetProjectDir());

		auto globOpts = Package.GetGlobalOptions();
		string precmd = getEnvironmentChanges();
		string[] files = getInputFileList();
		//quoteFilenames(files);

		if (mProjectOptions.compilationModel == ProjectOptions.kCompileThroughDub)
		{
			precmd ~= getDubCommandLine("build", rebuild) ~ "\n";
			link = false;
		}
		else if (compile)
		{
			string responsefile = GetCommandLinePath(false) ~ ".rsp";
			string fcmd = getCommandFileList(files, responsefile, precmd); // might append to precmd

			string[] srcfiles = getSourceFileList();
			string modules_ddoc;
			string mod_cmd = getModulesDDocCommandLine(srcfiles, modules_ddoc);
			if(mod_cmd.length > 0)
			{
				precmd ~= mod_cmd ~ "\nif %errorlevel% neq 0 goto reportError\n";
				fcmd ~= " " ~ modules_ddoc;
			}

			string opt = mProjectOptions.buildCommandLine(this, true, !separateLink && doLink, GetDependenciesPath(), false);

			if(separateLink || !doLink)
			{
				bool singleObj = mProjectOptions.isCombinedBuild();
				if(fcmd.length == 0)
					opt = ""; // don't try to build zero files
				else if(singleObj)
					opt ~= " -c" ~ mProjectOptions.getOutputFileOption("$(IntDir)\\$(ProjectName)." ~ mProjectOptions.objectFileExtension());
				else
					opt ~= " -c" ~ mProjectOptions.getObjectDirOption();
			}
			else if (mProjectOptions.lib != OutputType.StaticLib) // dmd concatenates object dir and output file
				opt ~= mProjectOptions.getObjectDirOption(); // dmd writes object file to $(OutDir) otherwise

			string addopt;
			if(mProjectOptions.additionalOptions.length && fcmd.length)
				addopt = " " ~ mProjectOptions.additionalOptions.replace("\n", " ");
			precmd ~= opt ~ fcmd ~ addopt ~ "\n";
		}
		string cmd = precmd;
		cmd ~= "if %errorlevel% neq 0 goto reportError\n";

		if(link && separateLink && doLink)
		{
			string prelnk, lnkcmd;
			if(mProjectOptions.callLinkerDirectly())
			{
				string libpaths, options;
				string otherCompiler = mProjectOptions.replaceEnvironment(mProjectOptions.otherCompilerPath(), this);
				string linkpath = globOpts.getLinkerPath(x64, mscoff, workdir, otherCompiler, &libpaths, &options);
				lnkcmd = quoteFilename(linkpath) ~ " ";

				if(globOpts.demangleError || globOpts.optlinkDeps)
					lnkcmd = "\"$(VisualDInstallDir)pipedmd.exe\" "
						~ (globOpts.demangleError ? null : "-nodemangle ")
						~ (mProjectOptions.usesMSLink() ? "-msmode " : null)
						~ (globOpts.optlinkDeps ? "-deps " ~ quoteFilename(GetLinkDependenciesPath()) ~ " " : null)
						~ lnkcmd;

				string[] lnkfiles = getObjectFileList(files); // convert D files to object files, but leaves anything else untouched
				string plus = mscoff ? " " : "+";
				string cmdfiles = mProjectOptions.optlinkCommandLine(lnkfiles, options, workdir, mscoff, plus);
				if(cmdfiles.length > 100)
				{
					string lnkresponsefile = GetCommandLinePath(true) ~ ".rsp";
					lnkresponsefile = makeFilenameAbsolute(lnkresponsefile, workdir);
					if(lnkresponsefile != quoteFilename(lnkresponsefile))
					{
						// optlink does not support quoted response files
						if(!std.file.exists(lnkresponsefile))
							collectException(std.file.write(lnkresponsefile, ""));
						string shortresponsefile = shortFilename(lnkresponsefile);
						if (shortresponsefile.empty || shortresponsefile != quoteFilename(shortresponsefile))
							lnkresponsefile = baseName(lnkresponsefile); // if short name generation fails, move it into the project folder
						else
							lnkresponsefile = shortresponsefile;
					}
					plus ~= " >> " ~ lnkresponsefile ~ "\necho ";
					cmdfiles = mProjectOptions.optlinkCommandLine(lnkfiles, options, workdir, mscoff, plus);

					prelnk ~= "echo. > " ~ lnkresponsefile ~ "\n";
					prelnk ~= "echo " ~ cmdfiles;
					prelnk ~= " >> " ~ lnkresponsefile ~ "\n";
					if (mscoff) // linker supports UTF16 response file
						prelnk ~= "\"$(VisualDInstallDir)mb2utf16.exe\" " ~ lnkresponsefile ~ "\n";
					prelnk ~= "\n";
					lnkcmd ~= "@" ~ lnkresponsefile;
				}
				else
					lnkcmd ~= cmdfiles;

				if(!mProjectOptions.useStdLibPath)
					prelnk = "set OPTLINKS=%OPTLINKS% /NOSCANLIB\n" ~ prelnk;
				prelnk = "set LIB=" ~ libpaths ~ "\n" ~ prelnk;
			}
			else
			{
				lnkcmd = mProjectOptions.buildCommandLine(this, false, true, GetLinkDependenciesPath());
				lnkcmd ~= getLinkFileList(files, prelnk);
				string addlnkopt = mProjectOptions.getAdditionalLinkOptions();
				if(addlnkopt.length)
					lnkcmd ~= " " ~ addlnkopt;
			}
			cmd = cmd ~ "\n" ~ prelnk ~ lnkcmd ~ "\n";
			cmd = cmd ~ "if %errorlevel% neq 0 goto reportError\n";
		}

		if (link)
		{
			string cv2pdb = mProjectOptions.appendCv2pdb();
			if(cv2pdb.length && doLink)
			{
				string cvtarget = quoteFilename(mProjectOptions.getCvTargetPath());
				cmd ~= "if not exist " ~ cvtarget ~ " (echo " ~ cvtarget ~ " not created! && goto reportError)\n";
				cmd ~= "echo Converting debug information...\n";
				cmd ~= cv2pdb;
				cmd ~= "\nif %errorlevel% neq 0 goto reportError\n";
			}

			string pre = strip(mProjectOptions.preBuildCommand);
			if(pre.length)
				cmd = pre ~ "\nif %errorlevel% neq 0 goto reportError\n" ~ cmd;

			string post = strip(mProjectOptions.postBuildCommand);
			if(post.length)
				cmd = cmd ~ "\nif %errorlevel% neq 0 goto reportError\n" ~ post ~ "\n\n";

			string target = quoteFilename(mProjectOptions.getTargetPath());
			cmd ~= "if not exist " ~ target ~ " (echo " ~ target ~ " not created! && goto reportError)\n";
		}
		cmd ~= "\ngoto noError\n";
		cmd ~= "\n:reportError\n";
		cmd ~= "echo Building " ~ GetTargetPath() ~ " failed!\n";
		cmd ~= "\n:noError\n";

		return mProjectOptions.replaceEnvironment(cmd, this);
	}

	bool writeLinkDependencyFile()
	{
		string workdir = normalizeDir(GetProjectDir());
		string depfile = makeFilenameAbsolute(GetDependenciesPath(), workdir);
		string[] files = getInputFileList();
		files = getObjectFileList(files);
		string prefix = "target (";
		string postfix = ") : public : object \n";
		string deps;
		foreach(f; files)
		{
			static if (usePipedmdForDeps)
				deps ~= f ~ "\n";
			else
				deps ~= prefix ~ replace(f, "\\", "\\\\") ~ postfix;
		}
		try
		{
			static if (usePipedmdForDeps)
			{
				int cp = GetKBCodePage();
				const(char)* depz = toMBSz(deps, cp);
				deps = cast(string)depz[0..strlen(depz)];
			}
			std.file.write(depfile, deps);
			return true;
		}
		catch(Exception e)
		{
		}
		return false;
	}

	extern(D)
	void processDependentProjects(scope void delegate(IVsProjectCfg) process)
	{
		auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
		if(!solutionBuildManager)
			return;

		scope(exit) release(solutionBuildManager);

		ULONG cActual;
		if(HRESULT hr = solutionBuildManager.GetProjectDependencies(mProvider.mProject, 0, null, &cActual))
			return;
		IVsHierarchy[] pHier = new IVsHierarchy [cActual];

		if(HRESULT hr = solutionBuildManager.GetProjectDependencies(mProvider.mProject, cActual, pHier.ptr, &cActual))
			return;

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
						cp2.GetCfgOfName(_toUTF16z(mName), _toUTF16z(mPlatform), &cfg);
						if(!cfg)
							cp2.GetCfgs(1, &cfg, null, null); // TODO: find a "similar" config?
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

				process(prjcfg);
			}
			release(pHier[i]);
		}
	}

	string[] getLibsFromDependentProjects()
	{
		string[] libs;
		processDependentProjects((IVsProjectCfg prjcfg)
		{
			debug logOutputGroups(prjcfg);

			version(none)
			if(auto prjcfg2 = qi_cast!IVsProjectCfg2(prjcfg))
			{
				scope(exit) release(prjcfg2);
				IVsOutputGroup outputGroup;
				if(prjcfg2.OpenOutputGroup(VS_OUTPUTGROUP_CNAME_Built, &outputGroup) == S_OK)
				{
					scope(exit) release(outputGroup);
					ULONG cnt;
					if(outputGroup.get_Outputs(0, null, &cnt) == S_OK)
					{
						auto outs = new IVsOutput2[cnt];
						if(outputGroup.get_Outputs(cnt, outs.ptr, null) == S_OK)
						{
							foreach(o; outs)
							{
								ScopedBSTR target;
								if(o.get_CanonicalName(&target.bstr) == S_OK)
								{
									string targ = target.detach();
									libs ~= targ;
								}
								release(o);
							}
						}
					}
				}
			}
			IVsEnumOutputs eo;
			if(prjcfg.EnumOutputs(&eo) == S_OK)
			{
				scope(exit) release(eo);
				ULONG fetched;
				string lastTarg;
				IVsOutput pIVsOutput;
				while(eo.Next(1, &pIVsOutput, &fetched) == S_OK && fetched == 1)
				{
					ScopedBSTR target;
					if(pIVsOutput.get_CanonicalName(&target.bstr) == S_OK)
					//if(pIVsOutput.get_DeploySourceURL(&target.bstr) == S_OK)
					//if(pIVsOutput.get_DisplayName(&target.bstr) == S_OK)
					{
						string targ = target.detach();
						if (lastTarg.length && targ.indexOf('$') >= 0)
						{
							// VC projects report the import library without expanding macros
							//  (even if building static libraries), so assume it lies along side the DLL
							if (targ.extension().toLower() == ".lib" && lastTarg.extension().toLower() != ".lib")
								targ = lastTarg.stripExtension() ~ ".lib";
							else
								targ = null;
						}
						if (targ.length)
						{
							libs ~= targ;
							lastTarg = targ;
						}
					}
					release(pIVsOutput);
				}
			}
		});
		return libs;
	}

	string[] getImportsFromDependentProjects()
	{
		string[] imports;
		string workdir = GetProjectDir().normalizeDir();
		processDependentProjects((IVsProjectCfg prjcfg)
		{
			if (auto cfg = qi_cast!Config(prjcfg))
			{
				string projdir = cfg.GetProjectDir();
				imports.addunique(projdir.makeRelative(workdir));
				string[] imps = tokenizeArgs(cfg.GetProjectOptions().imppath);
				foreach(imp; imps)
					imports.addunique(makeFilenameAbsolute(imp, projdir).makeRelative(workdir));
				release(cfg);
			}
		});
		return imports;
	}

	void logOutputGroups(IVsProjectCfg prjcfg)
	{
		if(auto prjcfg2 = qi_cast!IVsProjectCfg2(prjcfg))
		{
			scope(exit) release(prjcfg2);

			ULONG cntGroups;
			if(SUCCEEDED(prjcfg2.get_OutputGroups(0, null, &cntGroups)))
			{
				auto groups = new IVsOutputGroup[cntGroups];
				if(prjcfg2.get_OutputGroups(cntGroups, groups.ptr, &cntGroups) == S_OK)
				{
					foreach(outputGroup; groups)
					{
						scope(exit) release(outputGroup);

						BSTR bstrCanName, bstrDispName, bstrKeyOut, bstrDesc;
						outputGroup.get_CanonicalName(&bstrCanName);
						outputGroup.get_DisplayName(&bstrDispName);
						outputGroup.get_KeyOutput(&bstrKeyOut);
						outputGroup.get_Description(&bstrDesc);

						logCall("Group: %s Disp: %s KeyOut: %s Desc: %s", detachBSTR(bstrCanName), detachBSTR(bstrDispName), detachBSTR(bstrKeyOut), detachBSTR(bstrDesc));

						ULONG cnt;
						if(outputGroup.get_Outputs(0, null, &cnt) == S_OK)
						{
							auto outs = new IVsOutput2[cnt];
							if(outputGroup.get_Outputs(cnt, outs.ptr, &cnt) == S_OK)
							{
								foreach(o; outs)
								{
									BSTR target, display, url;
									o.get_CanonicalName(&target);
									o.get_DisplayName(&display);
									o.get_DeploySourceURL(&url);
									logCall("  Out: %s Disp: %s URL: %s", detachBSTR(target), detachBSTR(display), detachBSTR(url));

									release(o);
								}
							}
						}
					}
				}
			}
		}
	}

	int addJSONFiles(ref string[] files)
	{
		int cnt = 0;
		alias mProjectOptions opt;
		if(opt.doXGeneration)
		{
			void addJSONFile(string xfile)
			{
				xfile = makeFilenameAbsolute(xfile, GetProjectDir());
				if(xfile.length && std.file.exists(xfile))
				{
					addunique(files, xfile);
					cnt++;
				}
			}
			if(opt.compilationModel == ProjectOptions.kSingleFileCompilation)
			{
				searchNode(mProvider.mProject.GetRootNode(),
					delegate (CHierNode n) {
						if(CFileNode file = cast(CFileNode) n)
						{
							string tool = GetCompileTool(file);
							if(tool == "DMDsingle")
							{
								string outfile = GetOutputFile(file);
								string xfile = opt.replaceEnvironment(opt.xfilename, this, file.GetFilename(), outfile);
								addJSONFile(xfile);
							}
						}
						return false;
					});
			}
			else
			{
				string xfile = opt.replaceEnvironment(opt.xfilename, this);
				addJSONFile(xfile);
			}
		}
		return cnt;
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
		Package.scheduleUpdateLibrary();
	}

	CBuilderThread getBuilder() { return mBuilder; }

	string getName() { return mName; }
	string getPlatform() { return mPlatform; }
	string getCfgName() { return mName ~ "|" ~ mPlatform; }

private:
	string mName;
	string mPlatform;
	ConfigProvider mProvider;
	ProjectOptions mProjectOptions;
	CBuilderThread mBuilder;
	version(hasOutputGroup)
		VsOutputGroup mOutputGroup;

	ConfigModifiedListener[] mModifiedListener;
	IVsBuildStatusCallback[VSCOOKIE] mBuildStatusCallbacks;
	bool[VSCOOKIE] mTicking;
	bool[VSCOOKIE] mStarted;

	VSCOOKIE mLastBuildStatusCookie;
};


class DEnumOutFactory : DComObject, IClassFactory
{
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface2!(IClassFactory) (this, IID_IClassFactory, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		logCall("%s.CreateInstance(riid=%s)", this, _toLog(riid));

		assert(!UnkOuter);
		DEnumOutputs eo = newCom!DEnumOutputs(null, 0);
		return eo.QueryInterface(riid, pvObject);
	}
	override HRESULT LockServer(in BOOL fLock)
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
		{
			auto opt = cfg.mProjectOptions;
			mTargets ~= makeFilenameAbsolute(cfg.GetTargetPath(), cfg.GetProjectDir());
			if (opt.lib != OutputType.StaticLib && opt.createImplib)
			{
				mTargets ~= cfg.expandedAbsoluteFilename(opt.impfile);
			}
		}
		mPos = pos;
	}

	this(DEnumOutputs eo)
	{
		mTargets = eo.mTargets;
		mPos = eo.mPos;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
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
		*rgpIVsOutput = addref(newCom!VsOutput(mTargets[mPos]));
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

		*ppIVsEnumOutputs = addref(newCom!DEnumOutputs(this));
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

		*cast(GUID*)pCid = g_unmarshalEnumOutCLSID;
		return S_OK;
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

		DWORD size = iid.sizeof + int.sizeof;
		foreach(s; mTargets)
			size += int.sizeof + s.length;
		size += mPos.sizeof;
		*pSize = size;
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

		DEnumOutputs eo = newCom!DEnumOutputs(null, 0);
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

	override HRESULT ReleaseMarshalData(/+[in, unique]+/ IStream pStm)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}

	override HRESULT DisconnectObject(/+[in]+/ in DWORD dwReserved)
	{
		logCall("%s.DisconnectObject(dwReserved=%s)", this, _toLog(dwReserved));
		return returnError(E_NOTIMPL);
	}

}

class VsOutput : DComObject, IVsOutput2
{
	string mTarget;

	this(string target)
	{
		mTarget = target;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
	version(hasOutputGroup)
		if(queryInterface!(IVsOutput2) (this, riid, pvObject))
			return S_OK;
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

	// IVsOutput2
	HRESULT get_RootRelativeURL(/+[out]+/ BSTR *pbstrRelativePath)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	HRESULT get_Property(in LPCOLESTR szProperty, /+[out]+/ VARIANT *pvar)
	{
		mixin(LogCallMix);
		string prop = to_string(szProperty);
		if (icmp(prop, "OUTPUTLOC") == 0)
		{
			pvar.vt = VT_BSTR;
			pvar.bstrVal = allocBSTR(mTarget);
			return S_OK;
		}
		return returnError(E_NOTIMPL);
	}
}

class VsOutputGroup : DComObject, IVsOutputGroup
{
	this(Config cfg)
	{
		mConfig = cfg;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsOutputGroup) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// These return identical information regardless of cfg setting:
	HRESULT get_CanonicalName(/+[out]+/ BSTR *pbstrCanonicalName)
	{
		mixin(LogCallMix);
		*pbstrCanonicalName = allocBSTR(to_string(VS_OUTPUTGROUP_CNAME_Built));
		return S_OK;
	}

	HRESULT get_DisplayName(/+[out]+/ BSTR *pbstrDisplayName)
	{
		mixin(LogCallMix);
		*pbstrDisplayName = allocBSTR("Project build target");
		return S_OK;
	}

    // The results of these will vary based on the configuration:
    HRESULT get_KeyOutput(/+[out]+/ BSTR *pbstrCanonicalName)
	{
		mixin(LogCallMix);
		string target = makeFilenameAbsolute(mConfig.GetTargetPath(), mConfig.GetProjectDir());
		*pbstrCanonicalName = allocBSTR(target);
		return S_OK;
	}

    // Back pointer to project cfg:
    HRESULT get_ProjectCfg(/+[out]+/ IVsProjectCfg2 *ppIVsProjectCfg2)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

    // The list of outputs.  There might be none!  Not all files go out
    // on every configuration, and a groups files might all be configuration
    // dependent!
    HRESULT get_Outputs(in ULONG celt,
						/+[in, out, size_is(celt)]+/ IVsOutput2  *rgpcfg,
						/+[out, optional]+/ ULONG *pcActual)
	{
		mixin(LogCallMix);
		if(celt >= 1)
		{
			string target = makeFilenameAbsolute(mConfig.GetTargetPath(), mConfig.GetProjectDir());
			*rgpcfg = addref(newCom!VsOutput(target));
		}
		if(pcActual)
			*pcActual = 1;
		return S_OK;
	}

    HRESULT get_DeployDependencies(in ULONG celt,
								   /+[in,    out, size_is(celt)]+/ IVsDeployDependency  *rgpdpd,
								   /+[out, optional]+/ ULONG *pcActual)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

    HRESULT get_Description(/+[out]+/ BSTR *pbstrDescription)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

private:
	Config mConfig;
};

///////////////////////////////////////////////////////////////////////
version(hasProfilableConfig)
{
class TargetInfoFactory : DComObject, IClassFactory
{
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface2!(IClassFactory) (this, IID_IClassFactory, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		logCall("%s.CreateInstance(riid=%s)", this, _toLog(riid));

		assert(!UnkOuter);
		ProfilerTargetInfo pti = newCom!ProfilerTargetInfo(null);
		return pti.QueryInterface(riid, pvObject);
	}
	override HRESULT LockServer(in BOOL fLock)
	{
		return returnError(E_NOTIMPL);
	}
}

class ProfilerTargetInfo : DComObject, IVsProfilerTargetInfo, IVsProfilerLaunchExeTargetInfo, IMarshal
{
	string mPlatform;
	string mWorkdir;
	string mProgram;
	string mArgs;

	this(Config cfg)
	{
		if(cfg)
		{
			mPlatform = cfg.mPlatform;
			mWorkdir = cfg.mProjectOptions.replaceEnvironment(cfg.mProjectOptions.debugworkingdir, cfg);
			if(!isAbsolute(mWorkdir))
				mWorkdir = cfg.GetProjectDir() ~ "\\" ~ mWorkdir;
			mProgram = cfg.mProjectOptions.replaceEnvironment(cfg.mProjectOptions.debugtarget, cfg);
			if(!isAbsolute(mProgram))
				mProgram = makeFilenameAbsolute(mProgram, mWorkdir);
			mArgs = cfg.mProjectOptions.replaceEnvironment(cfg.mProjectOptions.debugarguments, cfg);
		}
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsProfilerTargetInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProfilerLaunchTargetInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProfilerLaunchExeTargetInfo) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IMarshal) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}
	// IVsProfilerTargetInfo
	HRESULT ProcessArchitecture(VSPROFILERPROCESSARCHTYPE* arch)
	{
		mixin(LogCallMix2);
		if(mPlatform == "x64")
			*arch = ARCH_X64;
		else
			*arch = ARCH_X86;
		return S_OK;
	}
	// IVsProfilerLaunchTargetInfo
	HRESULT References(SAFEARRAY* rgbstr)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
	HRESULT EnvironmentSettings(SAFEARRAY* pbstr)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
	HRESULT LaunchProfilerFlags(VSPROFILERLAUNCHOPTS* opts)
	{
		mixin(LogCallMix2);
		*opts = VSPLO_NOPROFILE; // to just launch the exe!?
		return S_OK;
	}
	// IVsProfilerLaunchExeTargetInfo
	HRESULT ExecutableArguments(BSTR* pbstr)
	{
		mixin(LogCallMix2);
		*pbstr = allocBSTR(mArgs);
		return S_OK;
	}
	HRESULT ExecutablePath (BSTR* pbstr)
	{
		mixin(LogCallMix2);
		*pbstr = allocBSTR(mProgram);
		return S_OK;
	}
	HRESULT WorkingDirectory (BSTR* pbstr)
	{
		mixin(LogCallMix2);
		*pbstr = allocBSTR(mWorkdir[0..$-1]);
		return S_OK;
	}

	// IMarshall
	override HRESULT GetUnmarshalClass(
		 /+[in]+/ in IID* riid,
		 /+[in, unique]+/ in void *pv,
		 /+[in]+/ in DWORD dwDestContext,
		 /+[in, unique]+/ in void *pvDestContext,
		 /+[in]+/ in DWORD mshlflags,
		 /+[out]+/ CLSID *pCid)
	{
		mixin(LogCallMixNoRet);

		*cast(GUID*)pCid = g_unmarshalTargetInfoCLSID;
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override HRESULT GetMarshalSizeMax(
		 /+[in]+/ in IID* riid,
		 /+[in, unique]+/ in void *pv,
		 /+[in]+/ in DWORD dwDestContext,
		 /+[in, unique]+/ in void *pvDestContext,
		 /+[in]+/ in DWORD mshlflags,
		 /+[out]+/ DWORD *pSize)
	{
		mixin(LogCallMixNoRet);

		DWORD size = iid.sizeof;
		size += int.sizeof + mPlatform.length;
		size += int.sizeof + mWorkdir.length;
		size += int.sizeof + mProgram.length;
		size += int.sizeof + mArgs.length;
		*pSize = size;
		return S_OK;
	}

	override HRESULT MarshalInterface(
		 /+[in, unique]+/ IStream pStm,
		 /+[in]+/ in IID* riid,
		 /+[in, unique]+/ in void *pv,
		 /+[in]+/ in DWORD dwDestContext,
		 /+[in, unique]+/ in void *pvDestContext,
		 /+[in]+/ in DWORD mshlflags)
	{
		mixin(LogCallMixNoRet);

		HRESULT hr = pStm.Write(cast(void*)&iid, iid.sizeof, null);

		void writeString(string s)
		{
			int length = s.length;
			if(hr == S_OK)
				hr = pStm.Write(&length, length.sizeof, null);
			if(hr == S_OK && length > 0)
				hr = pStm.Write(cast(void*)s.ptr, length, null);
		}
		writeString(mPlatform);
		writeString(mWorkdir);
		writeString(mProgram);
		writeString(mArgs);
		return hr;
	}

	override HRESULT UnmarshalInterface(
		 /+[in, unique]+/ IStream pStm,
		 /+[in]+/ in IID* riid,
		 /+[out]+/ void **ppv)
	{
		mixin(LogCallMix);

		GUID miid;
		HRESULT hr = pStm.Read(&miid, iid.sizeof, null);
		if (hr == S_OK)
			assert(miid == iid);

		void readString(ref string str)
		{
			int length;
			if(hr == S_OK)
				hr = pStm.Read(&length, length.sizeof, null);
			if(hr == S_OK)
			{
				char[] s = new char[length];
				hr = pStm.Read(s.ptr, length, null);
				if(hr == S_OK)
					str = assumeUnique(s);
			}
		}

		ProfilerTargetInfo pti = newCom!ProfilerTargetInfo(null);
		readString(pti.mPlatform);
		readString(pti.mWorkdir);
		readString(pti.mProgram);
		readString(pti.mArgs);
		if(hr != S_OK)
			return returnError(hr);

		return pti.QueryInterface(riid, ppv);
	}

	override HRESULT ReleaseMarshalData(/+[in, unique]+/ IStream pStm)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}

	override HRESULT DisconnectObject(/+[in]+/ in DWORD dwReserved)
	{
		logCall("%s.DisconnectObject(dwReserved=%s)", this, _toLog(dwReserved));
		return returnError(E_NOTIMPL);
	}

	int mExternalReferences;
}

class EnumVsProfilerTargetInfos : DComObject, IEnumVsProfilerTargetInfos
{
	Config mConfig;
	int mPos;

	this(Config cfg)
	{
		mConfig = cfg;
		mPos = 0;
	}
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface2!(IEnumVsProfilerTargetInfos) (this, uuid_IEnumVsProfilerTargetInfos, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT Next(in ULONG celt, IVsProfilerTargetInfo *rgelt, ULONG *pceltFetched)
	{
		ULONG fetched = 0;
		if(mPos == 0 && celt > 0)
		{
			*rgelt = addref(newCom!ProfilerTargetInfo(mConfig));
			fetched = 1;
			mPos++;
		}
		if(pceltFetched)
			*pceltFetched = fetched;
		return fetched > 0 ? S_OK : S_FALSE;
	}
	HRESULT Skip(in   ULONG celt)
	{
		mPos += celt;
		return S_OK;
	}
	HRESULT Reset()
	{
		mPos = 0;
		return S_OK;
	}
	HRESULT Clone(IEnumVsProfilerTargetInfos *ppenum)
	{
		*ppenum = addref(newCom!EnumVsProfilerTargetInfos(mConfig));
		return S_OK;
	}
}
} // version(hasProfilableConfig)

